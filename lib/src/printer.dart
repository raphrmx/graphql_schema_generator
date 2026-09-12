/// Prints an [SdlSchema] as GraphQL SDL.
///
/// The layout is the one `printSchema` from `graphql-js` produces, because that
/// is what every GraphQL tool expects to read: block string descriptions, a
/// blank line before a described field, arguments on one line unless one of
/// them is described, built-in scalars and built-in directives left out, and a
/// `schema { }` block only when a root type departs from its default name.
///
/// The order of the definitions is this package's own, and it is stable: the
/// directives first, sorted by name, then `Query`, `Mutation` and
/// `Subscription`, then every other type sorted by name. A schema read from
/// Dart sources has no natural definition order to preserve, and a stable one
/// is what lets a build fail on a real change rather than on a reshuffle.
library;

import 'package:graphql_schema_generator/src/model.dart';

/// The reason `@deprecated` carries when the SDL states none.
const String defaultDeprecationReason = 'No longer supported';

/// The five scalars the specification defines, which are never printed.
const Set<String> specifiedScalarNames = {
  'Int',
  'Float',
  'String',
  'Boolean',
  'ID',
};

/// The directives every server is expected to provide, which are never
/// printed.
const Set<String> specifiedDirectiveNames = {
  'skip',
  'include',
  'deprecated',
  'specifiedBy',
};

/// Prints [schema] as an SDL document, ending with a single newline.
String printSchema(SdlSchema schema) {
  final blocks = <String>[
    if (_needsSchemaBlock(schema)) _printSchemaBlock(schema),
    for (final directive in _orderedDirectives(schema))
      _printDirective(directive),
    for (final definition in _orderedDefinitions(schema))
      _printDefinition(definition),
  ];

  return '${blocks.join('\n\n')}\n';
}

/// The directives worth printing, sorted by name.
List<SdlDirective> _orderedDirectives(SdlSchema schema) =>
    schema.directives
        .where((d) => !specifiedDirectiveNames.contains(d.name))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

/// The type definitions worth printing, roots first and the rest by name.
List<SdlDefinition> _orderedDefinitions(SdlSchema schema) {
  final roots = <String>[
    ?schema.queryTypeName,
    ?schema.mutationTypeName,
    ?schema.subscriptionTypeName,
  ];

  final printable = schema.definitions
      .where((d) => !d.name.startsWith('__'))
      .where((d) => !(d is SdlScalar && specifiedScalarNames.contains(d.name)))
      .toList();

  final rootDefinitions = <SdlDefinition>[];
  for (final name in roots) {
    for (final definition in printable) {
      if (definition.name == name) rootDefinitions.add(definition);
    }
  }

  final rest = printable.where((d) => !rootDefinitions.contains(d)).toList()
    ..sort((a, b) => a.name.compareTo(b.name));

  return [...rootDefinitions, ...rest];
}

/// Whether the root types have to be spelled out in a `schema { }` block.
bool _needsSchemaBlock(SdlSchema schema) {
  final query = schema.queryTypeName;
  final mutation = schema.mutationTypeName;
  final subscription = schema.subscriptionTypeName;

  return (query != null && query != 'Query') ||
      (mutation != null && mutation != 'Mutation') ||
      (subscription != null && subscription != 'Subscription');
}

String _printSchemaBlock(SdlSchema schema) {
  final lines = <String>[
    if (schema.queryTypeName case final name?) '  query: $name',
    if (schema.mutationTypeName case final name?) '  mutation: $name',
    if (schema.subscriptionTypeName case final name?) '  subscription: $name',
  ];

  return 'schema {\n${lines.join('\n')}\n}';
}

String _printDefinition(SdlDefinition definition) => switch (definition) {
  SdlScalar() => _printScalar(definition),
  SdlEnum() => _printEnum(definition),
  SdlUnion() => _printUnion(definition),
  SdlInputObject() => _printInputObject(definition),
  SdlObject() => _printObject(definition),
};

String _printScalar(SdlScalar scalar) {
  final url = scalar.specifiedByUrl;
  final specifiedBy = url == null
      ? ''
      : ' @specifiedBy(url: ${printStringLiteral(url)})';

  return '${_printDescription(scalar.description)}'
      'scalar ${scalar.name}$specifiedBy'
      '${_printAppliedDirectives(scalar.directives)}';
}

String _printEnum(SdlEnum type) {
  final values = <String>[
    for (final (index, value) in type.values.indexed)
      _printEnumValue(value, firstInBlock: index == 0),
  ];

  return '${_printDescription(type.description)}'
      'enum ${type.name}${_printAppliedDirectives(type.directives)}'
      '${_printBlock(values)}';
}

String _printEnumValue(SdlEnumValue value, {required bool firstInBlock}) {
  final description = _printDescription(
    value.description,
    indentation: '  ',
    firstInBlock: firstInBlock,
  );

  return '$description  ${value.name}'
      '${_printDeprecated(value.deprecationReason)}'
      '${_printAppliedDirectives(value.directives)}';
}

String _printUnion(SdlUnion type) {
  final members = type.members.isEmpty ? '' : ' = ${type.members.join(' | ')}';
  return '${_printDescription(type.description)}union ${type.name}'
      '${_printAppliedDirectives(type.directives)}$members';
}

String _printInputObject(SdlInputObject type) =>
    '${_printDescription(type.description)}input ${type.name}'
    '${_printAppliedDirectives(type.directives)}'
    '${_printBlock(_printInputFields(type.fields))}';

String _printObject(SdlObject type) {
  final keyword = type.isInterface ? 'interface' : 'type';
  final implemented = type.interfaces.isEmpty
      ? ''
      : ' implements ${type.interfaces.join(' & ')}';

  return '${_printDescription(type.description)}'
      '$keyword ${type.name}$implemented'
      '${_printAppliedDirectives(type.directives)}'
      '${_printBlock(_printFields(type.fields))}';
}

List<String> _printFields(List<SdlField> fields) => [
  for (final (index, field) in fields.indexed)
    _printField(field, firstInBlock: index == 0),
];

String _printField(SdlField field, {required bool firstInBlock}) {
  final description = _printDescription(
    field.description,
    indentation: '  ',
    firstInBlock: firstInBlock,
  );

  return '$description  ${field.name}'
      '${_printArguments(field.arguments, '  ')}: ${printTypeRef(field.type)}'
      '${_printDeprecated(field.deprecationReason)}'
      '${_printAppliedDirectives(field.directives)}';
}

List<String> _printInputFields(List<SdlField> fields) => [
  for (final (index, field) in fields.indexed)
    _printInputField(field, firstInBlock: index == 0),
];

String _printInputField(SdlField field, {required bool firstInBlock}) {
  final description = _printDescription(
    field.description,
    indentation: '  ',
    firstInBlock: firstInBlock,
  );

  return '$description  '
      '${_printInputValue(field.name, field.type, field.defaultValue)}'
      '${_printDeprecated(field.deprecationReason)}'
      '${_printAppliedDirectives(field.directives)}';
}

String _printDirective(SdlDirective directive) {
  final repeatable = directive.isRepeatable ? ' repeatable' : '';
  return '${_printDescription(directive.description)}'
      'directive @${directive.name}'
      '${_printArguments(directive.arguments, '')}$repeatable'
      ' on ${directive.locations.join(' | ')}';
}

/// Arguments of a field or of a directive.
///
/// They go on one line, unless one of them carries a description: a
/// description has to sit on a line of its own, so the whole list opens up.
String _printArguments(List<SdlArgument> arguments, String indentation) {
  if (arguments.isEmpty) return '';

  if (arguments.every((a) => a.description == null)) {
    final printed = arguments.map(_printArgument).join(', ');
    return '($printed)';
  }

  final lines = <String>[
    for (final (index, argument) in arguments.indexed)
      _printDescribedArgument(argument, indentation, firstInBlock: index == 0),
  ];

  return '(\n${lines.join('\n')}\n$indentation)';
}

String _printDescribedArgument(
  SdlArgument argument,
  String indentation, {
  required bool firstInBlock,
}) {
  final description = _printDescription(
    argument.description,
    indentation: '$indentation  ',
    firstInBlock: firstInBlock,
  );

  return '$description$indentation  ${_printArgument(argument)}';
}

String _printArgument(SdlArgument argument) =>
    '${_printInputValue(argument.name, argument.type, argument.defaultValue)}'
    '${_printAppliedDirectives(argument.directives)}';

/// The directives applied at one place, each preceded by a space.
String _printAppliedDirectives(List<SdlAppliedDirective> directives) =>
    directives.isEmpty
    ? ''
    : ' ${directives.map(_printAppliedDirective).join(' ')}';

String _printAppliedDirective(SdlAppliedDirective directive) {
  if (directive.arguments.isEmpty) return '@${directive.name}';

  final printed = directive.arguments
      .map((a) => '${a.name}: ${a.value}')
      .join(', ');
  return '@${directive.name}($printed)';
}

String _printInputValue(String name, SdlTypeRef type, String? defaultValue) {
  final printed = '$name: ${printTypeRef(type)}';
  return defaultValue == null ? printed : '$printed = $defaultValue';
}

String _printDeprecated(String? reason) {
  if (reason == null) return '';
  if (reason == defaultDeprecationReason) return ' @deprecated';
  return ' @deprecated(reason: ${printStringLiteral(reason)})';
}

/// A block of members, or nothing at all when there are none.
String _printBlock(List<String> members) =>
    members.isEmpty ? '' : ' {\n${members.join('\n')}\n}';

/// Prints [type] the way it is written inside a schema, such as `[String!]!`.
String printTypeRef(SdlTypeRef type) => switch (type) {
  SdlNamedType(:final name) => name,
  SdlListType(:final of) => '[${printTypeRef(of)}]',
  SdlNonNullType(:final of) => '${printTypeRef(of)}!',
};

/// A description, indented and followed by a newline, or an empty string when
/// there is nothing to describe.
///
/// [firstInBlock] keeps the blank line out from between the opening brace and
/// the first member, where it would be noise rather than separation.
String _printDescription(
  String? description, {
  String indentation = '',
  bool firstInBlock = true,
}) {
  if (description == null) return '';

  final block = printBlockString(description);
  final prefix = indentation.isNotEmpty && !firstInBlock
      ? '\n$indentation'
      : indentation;

  return '$prefix${block.replaceAll('\n', '\n$indentation')}\n';
}

/// Prints [value] as a GraphQL block string.
///
/// Stays on one line for a short single-line value, and opens up when the
/// value spans lines, runs long, or ends with a character that would otherwise
/// swallow the closing quotes.
String printBlockString(String value) {
  final escaped = value.replaceAll('"""', r'\"""');
  final lines = escaped.split(RegExp(r'\r\n|[\n\r]'));
  final isSingleLine = lines.length == 1;

  final forceLeadingNewLine =
      lines.length > 1 &&
      lines.skip(1).every((l) => l.isEmpty || _isWhitespace(l.codeUnitAt(0)));
  final hasTrailingTripleQuotes = escaped.endsWith(r'\"""');
  final hasTrailingQuote = value.endsWith('"') && !hasTrailingTripleQuotes;
  final hasTrailingSlash = value.endsWith(r'\');
  final forceTrailingNewline = hasTrailingQuote || hasTrailingSlash;

  final printAsMultipleLines =
      !isSingleLine ||
      value.length > 70 ||
      forceTrailingNewline ||
      forceLeadingNewLine ||
      hasTrailingTripleQuotes;

  final skipLeadingNewLine =
      isSingleLine && value.isNotEmpty && _isWhitespace(value.codeUnitAt(0));

  final buffer = StringBuffer();
  if ((printAsMultipleLines && !skipLeadingNewLine) || forceLeadingNewLine) {
    buffer.write('\n');
  }
  buffer.write(escaped);
  if (printAsMultipleLines || forceTrailingNewline) buffer.write('\n');

  return '"""$buffer"""';
}

bool _isWhitespace(int code) => code == 0x9 || code == 0x20;

/// Prints [value] as a GraphQL string literal, quotes and escapes included.
String printStringLiteral(String value) {
  final buffer = StringBuffer('"');
  for (final rune in value.runes) {
    buffer.write(switch (rune) {
      0x22 => r'\"',
      0x5C => r'\\',
      0x08 => r'\b',
      0x0C => r'\f',
      0x0A => r'\n',
      0x0D => r'\r',
      0x09 => r'\t',
      _ when rune < 0x20 =>
        '\\u${rune.toRadixString(16).padLeft(4, '0').toUpperCase()}',
      _ => String.fromCharCode(rune),
    });
  }
  buffer.write('"');
  return buffer.toString();
}
