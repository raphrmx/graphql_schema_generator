/// Reads a package's Dart sources and builds the schema they describe.
///
/// The sources know nothing about GraphQL. A class is a type, its public
/// instance fields are the fields of that type, an enum is an enum, and the
/// methods of the classes named as roots are the operations. Nullability,
/// collections and documentation comments come straight from the Dart.
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:glob/glob.dart';
import 'package:graphql_schema_generator/src/config.dart';
import 'package:graphql_schema_generator/src/model.dart';
import 'package:graphql_schema_generator/src/naming.dart';
import 'package:path/path.dart' as p;

/// Thrown when the sources cannot be turned into a schema.
class SchemaReadException implements Exception {
  /// What went wrong, and where.
  final String message;

  /// Creates an exception carrying [message].
  SchemaReadException(this.message);

  @override
  String toString() => message;
}

/// Methods every class may carry and no schema ever wants.
const Set<String> _ignoredMethodNames = {
  'toJson',
  'toString',
  'noSuchMethod',
  'copyWith',
};

/// One class, waiting to be emitted in one position.
class _Pending {
  final ClassElement clazz;
  final bool isInput;

  const _Pending(this.clazz, this.isInput);
}

/// Builds an [SdlSchema] from the Dart sources of one package.
class SchemaReader {
  /// What to read, and how to name what comes out.
  final GeneratorConfig config;

  /// The root of the package being read, as an absolute path.
  final String packageRoot;

  late final AnalysisContextCollection _contexts;

  final List<_Pending> _pending = [];
  final Set<String> _seen = {};
  final Map<String, SdlDefinition> _definitions = {};
  final Set<String> _customScalars = {};

  /// Reads [packageRoot] according to [config].
  SchemaReader(this.config, {required this.packageRoot}) {
    _contexts = AnalysisContextCollection(
      includedPaths: [p.normalize(p.absolute(packageRoot))],
    );
  }

  /// Reads the sources and returns the schema they describe.
  Future<SdlSchema> read() async {
    final roots = <String, SdlObject>{};

    for (final entry in config.configuredRoots.entries) {
      roots[entry.key] = await _readRoot(entry.key, entry.value);
    }

    for (final element in await _includedElements()) {
      switch (element) {
        case ClassElement():
          _enqueue(element, isInput: false);
        case EnumElement():
          _readEnum(element);
        default:
          break;
      }
    }

    while (_pending.isNotEmpty) {
      final work = _pending.removeLast();
      if (work.isInput) {
        _readInputObject(work.clazz);
      } else {
        _readObject(work.clazz);
      }
    }

    final definitions = <SdlDefinition>[
      ...roots.values,
      for (final name in _customScalars) SdlScalar(name: name),
      ..._definitions.values,
    ];

    return SdlSchema(
      queryTypeName: roots.containsKey('Query') ? 'Query' : null,
      mutationTypeName: roots.containsKey('Mutation') ? 'Mutation' : null,
      subscriptionTypeName: roots.containsKey('Subscription')
          ? 'Subscription'
          : null,
      definitions: definitions,
    );
  }

  // ---------------------------------------------------------------- roots

  /// Reads the class named by [location], written `path/to/file.dart#Class`,
  /// and turns its public methods into the fields of the [typeName] root.
  Future<SdlObject> _readRoot(String typeName, String location) async {
    final parts = location.split('#');
    if (parts.length != 2 || parts.any((part) => part.trim().isEmpty)) {
      throw SchemaReadException(
        'The $typeName root is declared as "$location". It has to name a file '
        'and a class, as in lib/api/queries.dart#Queries.',
      );
    }

    final file = p.normalize(p.absolute(p.join(packageRoot, parts[0].trim())));
    final className = parts[1].trim();
    final library = await _library(file);

    final clazz = library.classes
        .where((c) => c.displayName == className)
        .firstOrNull;
    if (clazz == null) {
      throw SchemaReadException(
        'The $typeName root names the class $className, which ${parts[0]} does '
        'not declare.',
      );
    }

    final fields = <SdlField>[];
    for (final method in clazz.methods) {
      if (method.isStatic) continue;
      if (method.displayName.startsWith('_')) continue;
      if (_ignoredMethodNames.contains(method.displayName)) continue;

      fields.add(_readOperation(clazz, method));
    }

    if (fields.isEmpty) {
      throw SchemaReadException(
        'The $typeName root $className declares no public method, so the root '
        'would have no field. A GraphQL type with no field is not valid.',
      );
    }

    fields.sort((a, b) => a.name.compareTo(b.name));

    return SdlObject(
      name: typeName,
      description: documentationText(clazz.documentationComment),
      fields: fields,
    );
  }

  /// The type an operation answers with: what a `Future`, a `FutureOr` or a
  /// `Stream` carries, or the type itself when it carries nothing.
  DartType _unwrapAsync(DartType type) {
    if (type is! InterfaceType) return type;

    const wrappers = {'Future', 'FutureOr', 'Stream'};
    if (!wrappers.contains(type.element.displayName)) return type;
    if (type.typeArguments.isEmpty) return type;

    return type.typeArguments.first;
  }

  /// One method of a root class, as a field of that root.
  SdlField _readOperation(ClassElement clazz, MethodElement method) {
    final returnType = _unwrapAsync(method.returnType);
    final where = '${clazz.displayName}.${method.displayName}';

    final arguments = <SdlArgument>[];
    for (final parameter in method.formalParameters) {
      if (parameter.displayName.startsWith('_')) continue;

      arguments.add(
        SdlArgument(
          name: parameter.displayName,
          type: _typeRef(
            parameter.type,
            isInput: true,
            where: '$where(${parameter.displayName})',
          ),
          defaultValue: _sdlLiteral(parameter.defaultValueCode, parameter.type),
        ),
      );
    }

    return SdlField(
      name: method.displayName,
      type: _typeRef(returnType, isInput: false, where: where),
      description: documentationText(method.documentationComment),
      deprecationReason: _deprecationReason(method),
      arguments: arguments,
    );
  }

  // ---------------------------------------------------------------- types

  /// Emits [clazz] as an object type.
  void _readObject(ClassElement clazz) {
    final name = _typeNameOf(clazz, isInput: false);
    final fields = <SdlField>[];

    for (final field in _instanceFields(clazz)) {
      fields.add(
        SdlField(
          name: _fieldName(field),
          type: _typeRef(
            field.type,
            isInput: false,
            where: '${clazz.displayName}.${field.displayName}',
          ),
          description: documentationText(field.documentationComment),
          deprecationReason: _deprecationReason(field),
        ),
      );
    }

    _define(
      clazz,
      SdlObject(
        name: name,
        description: documentationText(clazz.documentationComment),
        isInterface: clazz.isAbstract,
        interfaces: [
          for (final interface in clazz.interfaces)
            if (interface.element is ClassElement)
              _typeNameOf(interface.element as ClassElement, isInput: false),
        ],
        fields: fields,
      ),
    );

    for (final interface in clazz.interfaces) {
      final element = interface.element;
      if (element is ClassElement) _enqueue(element, isInput: false);
    }
  }

  /// Emits [clazz] as an input object type.
  void _readInputObject(ClassElement clazz) {
    final name = _typeNameOf(clazz, isInput: true);
    final defaults = _constructorDefaults(clazz);
    final fields = <SdlField>[];

    for (final field in _instanceFields(clazz)) {
      fields.add(
        SdlField(
          name: _fieldName(field),
          type: _typeRef(
            field.type,
            isInput: true,
            where: '${clazz.displayName}.${field.displayName}',
          ),
          description: documentationText(field.documentationComment),
          deprecationReason: _deprecationReason(field),
          defaultValue: _sdlLiteral(defaults[field.displayName], field.type),
        ),
      );
    }

    _define(
      clazz,
      SdlInputObject(
        name: name,
        description: documentationText(clazz.documentationComment),
        fields: fields,
      ),
    );
  }

  /// Emits [element] as an enum type.
  void _readEnum(EnumElement element) {
    final name = graphQLTypeName(
      element.displayName,
      isInput: false,
      stripPrefixes: config.stripClassPrefixes,
      inputSuffix: config.inputSuffix,
    );
    if (_definitions.containsKey(name)) return;

    _definitions[name] = SdlEnum(
      name: name,
      description: documentationText(element.documentationComment),
      values: [
        for (final constant in element.constants)
          SdlEnumValue(
            name: constant.displayName,
            description: documentationText(constant.documentationComment),
            deprecationReason: _deprecationReason(constant),
          ),
      ],
    );
  }

  /// The GraphQL type a Dart type maps to, wrapped as the Dart nullability
  /// and the Dart collections say.
  SdlTypeRef _typeRef(
    DartType type, {
    required bool isInput,
    required String where,
  }) {
    final isNullable = type.nullabilitySuffix == NullabilitySuffix.question;
    final inner = _namedTypeRef(type, isInput: isInput, where: where);
    return isNullable ? inner : SdlNonNullType(inner);
  }

  SdlTypeRef _namedTypeRef(
    DartType type, {
    required bool isInput,
    required String where,
  }) {
    if (type is VoidType) {
      throw SchemaReadException(
        '$where answers with void. Every GraphQL field answers with a value, '
        'so an operation has to return one.',
      );
    }

    if (type is! InterfaceType) {
      throw SchemaReadException(
        'The type of $where is "${type.getDisplayString()}", which has no '
        'GraphQL equivalent. Give the field a class, an enum, a collection or '
        'a scalar.',
      );
    }

    if (type.isDartCoreString) return const SdlNamedType('String');
    if (type.isDartCoreInt) return const SdlNamedType('Int');
    if (type.isDartCoreDouble || type.isDartCoreNum) {
      return const SdlNamedType('Float');
    }
    if (type.isDartCoreBool) return const SdlNamedType('Boolean');

    if (type.isDartCoreList || type.isDartCoreSet || type.isDartCoreIterable) {
      final arguments = type.typeArguments;
      if (arguments.isEmpty) {
        throw SchemaReadException(
          'The collection at $where has no element type. A GraphQL list has to '
          'say what it holds.',
        );
      }
      return SdlListType(
        _typeRef(arguments.first, isInput: isInput, where: where),
      );
    }

    final element = type.element;
    final mapped = config.scalars[element.displayName];
    if (mapped != null) {
      _customScalars.add(mapped);
      return SdlNamedType(mapped);
    }

    if (element is EnumElement) {
      _readEnum(element);
      return SdlNamedType(
        graphQLTypeName(
          element.displayName,
          isInput: false,
          stripPrefixes: config.stripClassPrefixes,
          inputSuffix: config.inputSuffix,
        ),
      );
    }

    if (element is ClassElement) {
      if (type.isDartCoreMap || type.isDartCoreObject) {
        throw SchemaReadException(
          'The type of $where is "${type.getDisplayString()}", which GraphQL '
          'has no shape for. Replace it with a class, or map it to a scalar '
          'under `scalars:` in pubspec.yaml.',
        );
      }
      _enqueue(element, isInput: isInput);
      return SdlNamedType(_typeNameOf(element, isInput: isInput));
    }

    throw SchemaReadException(
      'The type of $where is "${type.getDisplayString()}", which this '
      'generator does not know how to describe.',
    );
  }

  // ------------------------------------------------------------- plumbing

  void _enqueue(ClassElement clazz, {required bool isInput}) {
    final key =
        '${clazz.library.uri}#${clazz.displayName}:'
        '${isInput ? 'in' : 'out'}';
    if (!_seen.add(key)) return;
    _pending.add(_Pending(clazz, isInput));
  }

  void _define(ClassElement clazz, SdlDefinition definition) {
    final existing = _definitions[definition.name];
    if (existing != null) {
      throw SchemaReadException(
        'Two Dart classes map to the GraphQL type ${definition.name}. Rename '
        'one of them, or drop a prefix under `strip_class_prefixes:` so they '
        'stop colliding.',
      );
    }
    _definitions[definition.name] = definition;
  }

  String _typeNameOf(ClassElement clazz, {required bool isInput}) =>
      graphQLTypeName(
        clazz.displayName,
        isInput: isInput,
        stripPrefixes: config.stripClassPrefixes,
        inputSuffix: config.inputSuffix,
      );

  /// The public instance fields of [clazz] and of its superclasses, nearest
  /// declaration first and each name kept once.
  List<FieldElement> _instanceFields(ClassElement clazz) {
    final collected = <FieldElement>[];
    InterfaceType? search = clazz.thisType;

    while (search != null && !search.isDartCoreObject) {
      final element = search.element;
      if (element is! ClassElement) break;

      for (final field in element.fields) {
        if (field.isStatic || !field.isOriginDeclaration) continue;
        if (field.displayName.startsWith('_')) continue;
        if (collected.any((f) => f.displayName == field.displayName)) continue;
        collected.add(field);
      }
      search = search.superclass;
    }

    return collected;
  }

  /// The name a field carries in the schema: its Dart name, unless
  /// `@JsonKey(name:)` already renamed it on the wire.
  String _fieldName(FieldElement field) {
    if (!config.honourJsonKey) return field.displayName;

    for (final annotation in field.metadata.annotations) {
      if (annotation.element?.enclosingElement?.displayName != 'JsonKey') {
        continue;
      }
      final value = annotation.computeConstantValue();
      final name = value?.getField('name')?.toStringValue();
      if (name != null && name.isNotEmpty) return name;
    }

    return field.displayName;
  }

  /// The reason [element] is deprecated, or null when it is not.
  String? _deprecationReason(Element element) {
    for (final annotation in element.metadata.annotations) {
      final enclosing = annotation.element?.enclosingElement?.displayName;
      if (enclosing != 'Deprecated') continue;

      final value = annotation.computeConstantValue();
      final message = value?.getField('message')?.toStringValue();
      return message == null || message.isEmpty ? 'Deprecated.' : message;
    }
    return null;
  }

  /// The default value written for each field in the constructor of [clazz],
  /// keyed by field name.
  Map<String, String> _constructorDefaults(ClassElement clazz) {
    final constructor = clazz.constructors
        .where((c) => c.displayName == clazz.displayName || c.name == 'new')
        .firstOrNull;
    if (constructor == null) return const {};

    return {
      for (final parameter in constructor.formalParameters)
        if (parameter.defaultValueCode != null)
          parameter.displayName: parameter.defaultValueCode!,
    };
  }

  /// A Dart default value written as an SDL literal, or null when it has no
  /// literal form the schema can carry.
  String? _sdlLiteral(String? code, DartType type) {
    if (code == null) return null;

    final trimmed = code.trim().replaceFirst(RegExp(r'^const\s+'), '').trim();
    if (trimmed.isEmpty || trimmed == 'null') return null;
    if (trimmed == 'true' || trimmed == 'false') return trimmed;
    if (RegExp(r'^-?\d+(\.\d+)?$').hasMatch(trimmed)) return trimmed;
    if (RegExp(r'^\[\s*\]$').hasMatch(trimmed)) return '[]';

    final string = RegExp(
      r"""^(['"])(.*)\1$""",
      dotAll: true,
    ).firstMatch(trimmed);
    if (string != null) {
      final body = string.group(2)!;
      if (body.contains(r'$')) return null;
      return '"${body.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
    }

    final element = type is InterfaceType ? type.element : null;
    if (element is EnumElement) {
      final dot = trimmed.lastIndexOf('.');
      if (dot > 0 && trimmed.startsWith(element.displayName)) {
        return trimmed.substring(dot + 1);
      }
    }

    return null;
  }

  // --------------------------------------------------------------- sources

  /// The classes and enums of the files the `include:` globs name.
  Future<List<Element>> _includedElements() async {
    if (config.include.isEmpty) return const [];

    final includes = config.include.map(Glob.new).toList();
    final excludes = config.exclude.map(Glob.new).toList();
    final elements = <Element>[];

    for (final file in _dartFiles()) {
      final relative = p
          .relative(file, from: packageRoot)
          .replaceAll(r'\', '/');
      if (!includes.any((g) => g.matches(relative))) continue;
      if (excludes.any((g) => g.matches(relative))) continue;

      final library = await _library(file);
      elements
        ..addAll(library.classes)
        ..addAll(library.enums);
    }

    return elements;
  }

  /// Every Dart file under the package, sorted so a run reads them in the same
  /// order as the one before.
  List<String> _dartFiles() {
    final directory = Directory(p.join(packageRoot, 'lib'));
    if (!directory.existsSync()) return const [];

    return directory
        .listSync(recursive: true)
        .whereType<File>()
        .map((file) => p.normalize(file.path))
        .where((path) => path.endsWith('.dart'))
        .toList()
      ..sort();
  }

  /// The resolved library of [file].
  Future<LibraryElement> _library(String file) async {
    final context = _contexts.contextFor(file);
    final unit = await context.currentSession.getResolvedUnit(file);

    if (unit is! ResolvedUnitResult) {
      throw SchemaReadException('Could not resolve $file.');
    }

    final failure = unit.diagnostics
        .where((d) => d.severity == Severity.error)
        .firstOrNull;
    if (failure != null) {
      throw SchemaReadException(
        '$file does not compile: ${failure.message}. The generator reads the '
        'resolved sources, so the package has to analyse cleanly first.',
      );
    }

    return unit.libraryElement;
  }
}
