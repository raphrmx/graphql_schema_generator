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
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:glob/glob.dart';
import 'package:graphql_schema_generator/src/config.dart';
import 'package:graphql_schema_generator/src/model.dart';
import 'package:graphql_schema_generator/src/naming.dart';
import 'package:graphql_schema_generator/src/printer.dart'
    show printStringLiteral;
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

/// The package the annotations the generator understands come from.
const String _annotationPackage = 'graphql_schema_annotation';

const String _locationScalar = 'SCALAR';
const String _locationObject = 'OBJECT';
const String _locationFieldDefinition = 'FIELD_DEFINITION';
const String _locationArgumentDefinition = 'ARGUMENT_DEFINITION';
const String _locationInterface = 'INTERFACE';
const String _locationUnion = 'UNION';
const String _locationEnum = 'ENUM';
const String _locationEnumValue = 'ENUM_VALUE';
const String _locationInputObject = 'INPUT_OBJECT';
const String _locationInputFieldDefinition = 'INPUT_FIELD_DEFINITION';

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
  final Map<String, SdlScalar> _customScalars = {};
  final Map<String, SdlDirective> _directives = {};
  final Map<String, ClassElement> _directiveSources = {};
  final Set<String> _declaring = {};

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
          if (_annotationValue(element, 'GraphQLDirective') case final value?) {
            _declareDirective(element, value);
          } else if (_scalarOf(element) case final scalar?) {
            _customScalars.putIfAbsent(scalar.name, () => scalar);
          } else {
            _enqueue(element, isInput: false);
          }
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
      } else if (work.clazz.isSealed) {
        _readUnion(work.clazz);
      } else {
        _readObject(work.clazz);
      }
    }

    final definitions = <SdlDefinition>[
      ...roots.values,
      ..._customScalars.values,
      ..._definitions.values,
    ];

    final schema = SdlSchema(
      queryTypeName: roots.containsKey('Query') ? 'Query' : null,
      mutationTypeName: roots.containsKey('Mutation') ? 'Mutation' : null,
      subscriptionTypeName: roots.containsKey('Subscription')
          ? 'Subscription'
          : null,
      directives: _directives.values.toList(),
      definitions: definitions,
    );

    final orphans = schema.unimplementedInterfaces;
    if (orphans.isNotEmpty) {
      final named = orphans.length == 1
          ? 'the interface ${orphans.single}'
          : 'the interfaces ${orphans.join(', ')}';
      throw SchemaReadException(
        'Nothing in the schema implements $named. A field answering with one '
        'could never resolve, and GraphQL calls such a schema valid all the '
        'same. A type reaches an interface through `implements` rather than '
        'through `extends`, a `sealed` class becomes a union of its subtypes '
        'instead, and `include:` brings in a type no operation mentions.',
      );
    }

    return schema;
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
      if (_isSkipped(clazz, clazz, method.displayName)) continue;
      if (_hasAnnotation(method, 'GraphQLSkip')) continue;

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
      directives: _appliedDirectives(clazz, _locationObject, clazz.displayName),
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
          directives: _appliedDirectives(
            parameter,
            _locationArgumentDefinition,
            '$where(${parameter.displayName})',
          ),
        ),
      );
    }

    return SdlField(
      name: method.displayName,
      type: _typeRef(returnType, isInput: false, where: where),
      description: documentationText(method.documentationComment),
      deprecationReason: _deprecationReason(method),
      arguments: arguments,
      directives: _appliedDirectives(method, _locationFieldDefinition, where),
    );
  }

  // ---------------------------------------------------------------- types

  /// Emits [clazz] as an object type.
  void _readObject(ClassElement clazz) {
    final name = _typeNameOf(clazz, isInput: false);
    final isInterface = _isInterface(clazz);
    final interfaces = _interfacesOf(clazz);
    final fields = <SdlField>[];

    for (final field in _instanceFields(clazz)) {
      fields.add(
        SdlField(
          name: field.displayName,
          type: _typeRef(
            field.type,
            isInput: false,
            where: '${clazz.displayName}.${field.displayName}',
          ),
          description: _describeField(clazz, field),
          deprecationReason: _fieldDeprecation(field),
          directives: _fieldDirectives(
            field,
            _locationFieldDefinition,
            _memberName(clazz, field),
          ),
        ),
      );
    }

    if (fields.isEmpty) {
      throw SchemaReadException(
        '${clazz.displayName} exposes no public instance field, so the type '
        'would have none. A GraphQL type holds at least one field.',
      );
    }

    _define(
      clazz,
      SdlObject(
        name: name,
        description: documentationText(clazz.documentationComment),
        directives: _appliedDirectives(
          clazz,
          isInterface ? _locationInterface : _locationObject,
          clazz.displayName,
        ),
        isInterface: isInterface,
        interfaces: [
          for (final interface in interfaces)
            _typeNameOf(interface, isInput: false),
        ],
        fields: fields,
      ),
    );

    for (final interface in interfaces) {
      _enqueue(interface, isInput: false);
    }
  }

  /// Emits the sealed class [clazz] as a union.
  ///
  /// A sealed class is a union the language already writes down: Dart makes
  /// every direct subtype live in the same library, so the members are known
  /// rather than guessed.
  void _readUnion(ClassElement clazz) {
    final members = _unionMembers(clazz, clazz);

    if (members.isEmpty) {
      throw SchemaReadException(
        'The sealed class ${clazz.displayName} has no subtype, so the union '
        'would have no member. A GraphQL union holds at least one type.',
      );
    }

    for (final member in members) {
      _enqueue(member, isInput: false);
    }

    _define(
      clazz,
      SdlUnion(
        name: _typeNameOf(clazz, isInput: false),
        description: documentationText(clazz.documentationComment),
        directives: _appliedDirectives(
          clazz,
          _locationUnion,
          clazz.displayName,
        ),
        members: [
          for (final member in members) _typeNameOf(member, isInput: false),
        ],
      ),
    );
  }

  /// The concrete subtypes of the sealed class [clazz], with a nested sealed
  /// hierarchy flattened: GraphQL has no union of unions.
  List<ClassElement> _unionMembers(ClassElement clazz, ClassElement root) {
    final members = <ClassElement>[];

    for (final candidate in clazz.library.classes) {
      if (candidate == clazz) continue;
      if (!_extendsDirectly(candidate, clazz)) continue;

      if (candidate.isSealed) {
        members.addAll(_unionMembers(candidate, root));
        continue;
      }
      if (candidate.isAbstract) {
        throw SchemaReadException(
          '${candidate.displayName} is an abstract subtype of the sealed class '
          '${root.displayName}. A GraphQL union holds object types, so every '
          'member of the hierarchy has to be a class that can be built.',
        );
      }
      members.add(candidate);
    }

    members.sort((a, b) => a.displayName.compareTo(b.displayName));
    return members;
  }

  /// Whether [candidate] names [parent] as its direct supertype, interface or
  /// mixin.
  bool _extendsDirectly(ClassElement candidate, ClassElement parent) =>
      candidate.supertype?.element == parent ||
      candidate.interfaces.any((i) => i.element == parent) ||
      candidate.mixins.any((m) => m.element == parent);

  /// Emits [clazz] as an input object type.
  void _readInputObject(ClassElement clazz) {
    final name = _typeNameOf(clazz, isInput: true);
    final defaults = _constructorDefaults(clazz);
    final fields = <SdlField>[];

    for (final field in _instanceFields(clazz)) {
      fields.add(
        SdlField(
          name: field.displayName,
          type: _typeRef(
            field.type,
            isInput: true,
            where: '${clazz.displayName}.${field.displayName}',
          ),
          description: _describeField(clazz, field),
          deprecationReason: _fieldDeprecation(field),
          defaultValue: _sdlLiteral(defaults[field.displayName], field.type),
          directives: _fieldDirectives(
            field,
            _locationInputFieldDefinition,
            _memberName(clazz, field),
          ),
        ),
      );
    }

    _define(
      clazz,
      SdlInputObject(
        name: name,
        description: documentationText(clazz.documentationComment),
        directives: _appliedDirectives(
          clazz,
          _locationInputObject,
          clazz.displayName,
        ),
        fields: fields,
      ),
    );
  }

  /// Emits [element] as an enum type.
  void _readEnum(EnumElement element) {
    final name = graphQLTypeName(element.displayName, isInput: false);
    if (_definitions.containsKey(name)) return;

    _definitions[name] = SdlEnum(
      name: name,
      description: documentationText(element.documentationComment),
      directives: _appliedDirectives(
        element,
        _locationEnum,
        element.displayName,
      ),
      values: [
        for (final constant in element.constants)
          SdlEnumValue(
            name: constant.displayName,
            description: documentationText(constant.documentationComment),
            deprecationReason: _deprecationReason(constant),
            directives: _appliedDirectives(
              constant,
              _locationEnumValue,
              '${element.displayName}.${constant.displayName}',
            ),
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

    if (_scalarOf(element) case final scalar?) {
      _customScalars.putIfAbsent(scalar.name, () => scalar);
      return SdlNamedType(scalar.name);
    }

    final mapped = config.scalars[element.displayName];
    if (mapped != null) {
      _customScalars.putIfAbsent(mapped, () => SdlScalar(name: mapped));
      return SdlNamedType(mapped);
    }

    if (element is EnumElement) {
      _readEnum(element);
      return SdlNamedType(graphQLTypeName(element.displayName, isInput: false));
    }

    // An extension type is a name over another type, and the wire carries the
    // type underneath. Naming it under `scalars:` is what turns it into a
    // scalar of its own, which is how a field reaches `ID`.
    if (element is ExtensionTypeElement) {
      return _namedTypeRef(element.typeErasure, isInput: isInput, where: where);
    }

    if (element is ClassElement) {
      if (type.isDartCoreMap || type.isDartCoreObject) {
        throw SchemaReadException(
          'The type of $where is "${type.getDisplayString()}", which GraphQL '
          'has no shape for. Replace it with a class, or map it to a scalar '
          'under `scalars:` in pubspec.yaml.',
        );
      }
      if (element.isSealed && isInput) {
        throw SchemaReadException(
          'The type of $where is the sealed class ${element.displayName}, '
          'which becomes a union. GraphQL has no union in input position, so '
          'an argument cannot carry one.',
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
        'Two Dart classes map to the GraphQL type ${definition.name}. A type '
        'name in the schema is the name of the class it came from, so two '
        'classes cannot share one unless one of them is renamed.',
      );
    }
    _definitions[definition.name] = definition;
  }

  String _typeNameOf(ClassElement clazz, {required bool isInput}) =>
      graphQLTypeName(clazz.displayName, isInput: isInput);

  /// The public instance fields of [clazz] and of its superclasses, nearest
  /// declaration first and each name kept once.
  ///
  /// A computed getter counts: the analyser gives it a field of its own, and
  /// something a class exposes as a value is a field of the type whether it is
  /// stored or worked out. A write-only property is left out, having nothing
  /// to read.
  List<FieldElement> _instanceFields(ClassElement clazz) {
    final collected = <FieldElement>[];
    InterfaceType? search = clazz.thisType;

    while (search != null && !search.isDartCoreObject) {
      final element = search.element;
      if (element is! ClassElement) break;

      for (final field in element.fields) {
        if (field.isStatic || field.getter == null) continue;
        if (field.displayName.startsWith('_')) continue;
        if (_isSkipped(clazz, element, field.displayName)) continue;
        if (_isSkippedField(field)) continue;
        if (collected.any((f) => f.displayName == field.displayName)) continue;
        collected.add(field);
      }
      search = search.superclass;
    }

    return collected;
  }

  /// Whether the configuration leaves [memberName] out of the schema.
  ///
  /// Matched against the class being emitted and against the one that declares
  /// the member, so an inherited member can be named either way.
  bool _isSkipped(ClassElement emitted, ClassElement declaring, String name) =>
      config.skip.contains('${emitted.displayName}.$name') ||
      config.skip.contains('${declaring.displayName}.$name');

  /// The description of [field] as [clazz] exposes it.
  ///
  /// When [clazz] says nothing, the interface or the superclass that also
  /// declares the field does, the way a Dart doc comment is inherited.
  String? _describeField(ClassElement clazz, FieldElement field) {
    final own = _fieldDescription(field);
    if (own != null) return own;

    for (final supertype in clazz.allSupertypes) {
      final element = supertype.element;
      if (element is! ClassElement) continue;

      for (final inherited in element.fields) {
        if (inherited.displayName != field.displayName) continue;

        final described = _fieldDescription(inherited);
        if (described != null) return described;
      }
    }

    return null;
  }

  /// The description of [field], which for a computed getter lives on the
  /// getter rather than on the field the analyser made for it.
  String? _fieldDescription(FieldElement field) =>
      documentationText(field.documentationComment) ??
      documentationText(field.getter?.documentationComment);

  /// The deprecation of [field], read from the getter when the field itself
  /// carries none, for the same reason.
  String? _fieldDeprecation(FieldElement field) {
    final onField = _deprecationReason(field);
    if (onField != null) return onField;

    final getter = field.getter;
    return getter == null ? null : _deprecationReason(getter);
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

  // ----------------------------------------------------------- annotations

  /// Whether [element] is the class [name] of the annotation package.
  bool _isAnnotationClass(Element? element, String name) {
    if (element == null || element.displayName != name) return false;

    final uri = element.library?.uri;
    return uri != null &&
        uri.scheme == 'package' &&
        uri.pathSegments.isNotEmpty &&
        uri.pathSegments.first == _annotationPackage;
  }

  /// The value of the [name] annotation [element] carries, or null when it
  /// carries none.
  DartObject? _annotationValue(Element element, String name) {
    for (final annotation in element.metadata.annotations) {
      final value = annotation.computeConstantValue();
      final type = value?.type;
      if (type is! InterfaceType) continue;
      if (_isAnnotationClass(type.element, name)) return value;
    }
    return null;
  }

  /// Whether [element] carries the [name] annotation.
  bool _hasAnnotation(Element element, String name) =>
      _annotationValue(element, name) != null;

  /// Whether [field] is kept out of the schema by an annotation, which for a
  /// computed getter sits on the getter.
  bool _isSkippedField(FieldElement field) {
    if (_hasAnnotation(field, 'GraphQLSkip')) return true;

    final getter = field.getter;
    return getter != null && _hasAnnotation(getter, 'GraphQLSkip');
  }

  /// Whether [clazz] is written as an interface rather than as a type.
  ///
  /// An abstract class is one. A sealed class is a union instead, and marking
  /// one changes nothing.
  bool _isInterface(ClassElement clazz) {
    if (clazz.isSealed) return false;
    return clazz.isAbstract || _hasAnnotation(clazz, 'GraphQLInterface');
  }

  /// The interfaces [clazz] declares in the schema, sorted by name.
  ///
  /// A class reached through `implements` is one: Dart `implements` is a
  /// promise about shape, which is what a GraphQL interface is. A superclass
  /// is one only when it carries `@GraphQLInterface`, `extends` being
  /// implementation reuse, whose fields are read into the type instead.
  List<ClassElement> _interfacesOf(ClassElement clazz) {
    final found = <ClassElement>{};

    void walk(ClassElement from) {
      for (final interface in from.interfaces) {
        final element = interface.element;
        if (element is! ClassElement) continue;

        if (_isInterface(element)) found.add(element);
        walk(element);
      }

      final supertype = from.supertype;
      if (supertype == null || supertype.isDartCoreObject) return;

      final superclass = supertype.element;
      if (superclass is! ClassElement) return;

      if (_hasAnnotation(superclass, 'GraphQLInterface')) found.add(superclass);
      walk(superclass);
    }

    walk(clazz);
    found.remove(clazz);

    return found.toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
  }

  /// The scalar [element] is carried as, or null when it is not one.
  SdlScalar? _scalarOf(Element element) {
    final value = _annotationValue(element, 'GraphQLScalar');
    if (value == null) return null;

    final name = value.getField('name')?.toStringValue();
    if (name == null || name.isEmpty) {
      throw SchemaReadException(
        'The @GraphQLScalar on ${element.displayName} names no scalar. A '
        'scalar has to say what it is called in the schema.',
      );
    }

    return SdlScalar(
      name: name,
      description: documentationText(element.documentationComment),
      specifiedByUrl: value.getField('specifiedByUrl')?.toStringValue(),
      directives: _appliedDirectives(
        element,
        _locationScalar,
        element.displayName,
      ),
    );
  }

  /// `Class.member`, the way a message and a `skip:` entry spell it.
  String _memberName(ClassElement clazz, FieldElement field) =>
      '${clazz.displayName}.${field.displayName}';

  /// The directives applied to [field], which for a computed getter sit on the
  /// getter.
  List<SdlAppliedDirective> _fieldDirectives(
    FieldElement field,
    String location,
    String where,
  ) {
    final onField = _appliedDirectives(field, location, where);
    if (onField.isNotEmpty) return onField;

    final getter = field.getter;
    return getter == null
        ? const []
        : _appliedDirectives(getter, location, where);
  }

  /// The directives [element] carries, each declared the first time it is met.
  ///
  /// [location] is the SDL location [element] stands at, and [where] names the
  /// place a message points to.
  List<SdlAppliedDirective> _appliedDirectives(
    Element element,
    String location,
    String where,
  ) {
    final applied = <SdlAppliedDirective>[];
    final seen = <String>{};

    for (final annotation in element.metadata.annotations) {
      final value = annotation.computeConstantValue();
      final type = value?.type;
      if (type is! InterfaceType) continue;

      final clazz = type.element;
      if (clazz is! ClassElement) continue;

      final declaration = _annotationValue(clazz, 'GraphQLDirective');
      if (declaration == null) continue;

      final directive = _declareDirective(clazz, declaration);

      if (!directive.locations.contains(location)) {
        throw SchemaReadException(
          '@${directive.name} is applied at $where, which the schema writes as '
          '$location. The directive is declared on '
          '${directive.locations.join(' | ')}.',
        );
      }
      if (!seen.add(directive.name) && !directive.isRepeatable) {
        throw SchemaReadException(
          '@${directive.name} is applied twice at $where. A directive applied '
          'more than once at one place has to be declared repeatable.',
        );
      }

      applied.add(
        SdlAppliedDirective(
          name: directive.name,
          arguments: _directiveArguments(directive, value, where),
        ),
      );
    }

    return applied;
  }

  /// The values one application of [directive] gives to its arguments.
  List<SdlArgumentValue> _directiveArguments(
    SdlDirective directive,
    DartObject? value,
    String where,
  ) {
    final given = <SdlArgumentValue>[];

    for (final argument in directive.arguments) {
      final field = value?.getField(argument.name);
      if (field == null || field.isNull) continue;

      final printed = _sdlValue(field);
      if (printed == null) {
        throw SchemaReadException(
          'The ${argument.name} argument of @${directive.name} at $where holds '
          'a value with no GraphQL literal. Give it a string, a number, a '
          'boolean, an enum value, or a list of those.',
        );
      }

      given.add(SdlArgumentValue(name: argument.name, value: printed));
    }

    return given;
  }

  /// Declares [clazz] as a directive, once.
  SdlDirective _declareDirective(ClassElement clazz, DartObject declaration) {
    final name = declaration.getField('name')?.toStringValue();
    if (name == null || name.isEmpty) {
      throw SchemaReadException(
        'The @GraphQLDirective on ${clazz.displayName} names no directive. A '
        'directive has to say what it is called in the schema.',
      );
    }

    final known = _directives[name];
    if (known != null) {
      final source = _directiveSources[name];
      if (source != null && source != clazz) {
        throw SchemaReadException(
          'Both ${source.displayName} and ${clazz.displayName} declare the '
          'directive @$name. A directive is declared once.',
        );
      }
      return known;
    }

    if (!_declaring.add(name)) {
      throw SchemaReadException(
        'The directive @$name takes an argument that leads back to @$name.',
      );
    }

    final locations = <String>[
      for (final location
          in declaration.getField('on')?.toSetValue() ?? const <DartObject>{})
        ?location.getField('sdlName')?.toStringValue(),
    ]..sort();

    if (locations.isEmpty) {
      throw SchemaReadException(
        'The directive @$name declares no location, so nothing could carry it.',
      );
    }

    final defaults = _constructorDefaults(clazz);
    final directive = SdlDirective(
      name: name,
      description: documentationText(clazz.documentationComment),
      isRepeatable: declaration.getField('repeatable')?.toBoolValue() ?? false,
      locations: locations,
      arguments: [
        for (final field in _instanceFields(clazz))
          SdlArgument(
            name: field.displayName,
            type: _typeRef(
              field.type,
              isInput: true,
              where: '@$name(${field.displayName})',
            ),
            description: _fieldDescription(field),
            defaultValue: _sdlLiteral(defaults[field.displayName], field.type),
          ),
      ],
    );

    _declaring.remove(name);
    _directives[name] = directive;
    _directiveSources[name] = clazz;
    return directive;
  }

  /// [value] written as an SDL literal, or null when it has no literal form.
  String? _sdlValue(DartObject value) {
    if (value.isNull) return 'null';

    if (value.toBoolValue() case final boolean?) return '$boolean';
    if (value.toIntValue() case final integer?) return '$integer';
    if (value.toDoubleValue() case final float?) return '$float';
    if (value.toStringValue() case final string?) {
      return printStringLiteral(string);
    }

    final items = value.toListValue() ?? value.toSetValue()?.toList();
    if (items != null) {
      final printed = <String>[];
      for (final item in items) {
        final one = _sdlValue(item);
        if (one == null) return null;
        printed.add(one);
      }
      return '[${printed.join(', ')}]';
    }

    final type = value.type;
    if (type is InterfaceType && type.element is EnumElement) {
      return value.variable?.displayName;
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
