/// The schema, as this package understands it between reading the Dart sources
/// and printing the SDL.
///
/// Everything here is plain data. The readers fill it in, the printer walks it,
/// and neither knows about the other.
library;

import 'package:collection/collection.dart';

/// A reference to a type, at the point where a field or an argument uses it.
sealed class SdlTypeRef {
  const SdlTypeRef();

  /// The name of the type at the bottom of the wrappers.
  String get baseName;
}

/// A type used by name, such as `String` or `_Product`.
class SdlNamedType extends SdlTypeRef {
  /// The name of the type, as it appears in the SDL.
  final String name;

  const SdlNamedType(this.name);

  @override
  String get baseName => name;
}

/// A list of [of], printed as `[of]`.
class SdlListType extends SdlTypeRef {
  /// The type of the list elements.
  final SdlTypeRef of;

  const SdlListType(this.of);

  @override
  String get baseName => of.baseName;
}

/// A type that cannot be null, printed as `of!`.
class SdlNonNullType extends SdlTypeRef {
  /// The type made non-nullable.
  final SdlTypeRef of;

  const SdlNonNullType(this.of);

  @override
  String get baseName => of.baseName;
}

/// An argument of a field, or of a directive.
class SdlArgument {
  /// The name of the argument.
  final String name;

  /// The type values must conform to.
  final SdlTypeRef type;

  /// The description, or null when the source carries none.
  final String? description;

  /// The default value, already written as an SDL literal, or null when the
  /// argument has none.
  final String? defaultValue;

  const SdlArgument({
    required this.name,
    required this.type,
    this.description,
    this.defaultValue,
  });
}

/// A field of an object type, of an interface, or of an input type.
class SdlField {
  /// The name of the field.
  final String name;

  /// The type of the value the field holds.
  final SdlTypeRef type;

  /// The description, or null when the source carries none.
  final String? description;

  /// The reason the field is deprecated, or null when it is not.
  final String? deprecationReason;

  /// The arguments the field takes. Always empty on an input field, which the
  /// GraphQL specification gives no arguments.
  final List<SdlArgument> arguments;

  /// The default value of an input field, already written as an SDL literal.
  final String? defaultValue;

  const SdlField({
    required this.name,
    required this.type,
    this.description,
    this.deprecationReason,
    this.arguments = const [],
    this.defaultValue,
  });
}

/// A value of an enum type.
class SdlEnumValue {
  /// The name of the value, as the schema exposes it.
  final String name;

  /// The description, or null when the source carries none.
  final String? description;

  /// The reason the value is deprecated, or null when it is not.
  final String? deprecationReason;

  const SdlEnumValue({
    required this.name,
    this.description,
    this.deprecationReason,
  });
}

/// A type definition.
sealed class SdlDefinition {
  /// The name of the type, as it appears in the SDL.
  final String name;

  /// The description, or null when the source carries none.
  final String? description;

  const SdlDefinition({required this.name, this.description});
}

/// An object type, or an interface when [isInterface] is set.
class SdlObject extends SdlDefinition {
  /// Whether the type is printed as `interface` rather than `type`.
  final bool isInterface;

  /// The names of the interfaces the type implements.
  final List<String> interfaces;

  /// The fields the type exposes.
  final List<SdlField> fields;

  const SdlObject({
    required super.name,
    super.description,
    this.isInterface = false,
    this.interfaces = const [],
    this.fields = const [],
  });
}

/// An input object type.
class SdlInputObject extends SdlDefinition {
  /// The fields the type accepts.
  final List<SdlField> fields;

  const SdlInputObject({
    required super.name,
    super.description,
    this.fields = const [],
  });
}

/// An enum type.
class SdlEnum extends SdlDefinition {
  /// The values the type accepts.
  final List<SdlEnumValue> values;

  const SdlEnum({
    required super.name,
    super.description,
    this.values = const [],
  });
}

/// A union type.
class SdlUnion extends SdlDefinition {
  /// The names of the types the union is made of.
  final List<String> members;

  const SdlUnion({
    required super.name,
    super.description,
    this.members = const [],
  });
}

/// A scalar type other than the five the specification defines.
class SdlScalar extends SdlDefinition {
  /// The URL of the specification of the scalar, printed as `@specifiedBy`,
  /// or null when there is none.
  final String? specifiedByUrl;

  const SdlScalar({
    required super.name,
    super.description,
    this.specifiedByUrl,
  });
}

/// A directive definition.
class SdlDirective {
  /// The name of the directive, without the leading `@`.
  final String name;

  /// The description, or null when the source carries none.
  final String? description;

  /// Whether the directive may be applied more than once at one location.
  final bool isRepeatable;

  /// The locations the directive may be applied at, spelled as the
  /// specification spells them, such as `FIELD_DEFINITION`.
  final List<String> locations;

  /// The arguments the directive takes.
  final List<SdlArgument> arguments;

  const SdlDirective({
    required this.name,
    required this.locations,
    this.description,
    this.isRepeatable = false,
    this.arguments = const [],
  });
}

/// A whole schema, ready to print.
class SdlSchema {
  /// The name of the type queries start from, or null when the schema has no
  /// query root.
  final String? queryTypeName;

  /// The name of the type mutations start from, or null when the schema has
  /// none.
  final String? mutationTypeName;

  /// The name of the type subscriptions start from, or null when the schema
  /// has none.
  final String? subscriptionTypeName;

  /// The directive definitions.
  final List<SdlDirective> directives;

  /// The type definitions.
  final List<SdlDefinition> definitions;

  const SdlSchema({
    this.queryTypeName,
    this.mutationTypeName,
    this.subscriptionTypeName,
    this.directives = const [],
    this.definitions = const [],
  });

  /// The definition named [name], or null when the schema holds none.
  SdlDefinition? definitionNamed(String name) =>
      definitions.firstWhereOrNull((d) => d.name == name);
}
