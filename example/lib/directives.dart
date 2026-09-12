import 'package:acme_catalogue/models/role.dart';
import 'package:graphql_schema_annotation/graphql_schema_annotation.dart';

/// Reads of this type are written to the audit log.
// A directive with no argument: the class is empty, and applying it is
// writing `@Audited()` on a class.
@GraphQLDirective(name: 'audited', on: {DirectiveLocation.object})
class Audited {
  /// Applies the directive.
  const Audited();
}

/// The value holds between [min] and [max] characters.
// The fields of the class are the arguments of the directive, and a default
// written in the constructor becomes the default of the argument. The schema
// enforces none of it, so the class carrying the directive asserts the same
// rule.
@GraphQLDirective(
  name: 'length',
  on: {
    DirectiveLocation.inputFieldDefinition,
    DirectiveLocation.argumentDefinition,
  },
)
class Length {
  /// The shortest value the field accepts.
  final int min;

  /// The longest value the field accepts.
  final int max;

  /// Applies the directive.
  const Length({required this.max, this.min = 1});
}

/// Only the listed roles read the field.
// No assert to pair with this one. An annotation has to be a const
// expression, and constant evaluation cannot reach into a list, so a rule
// about `roles` can only be checked where the values are read.
@GraphQLDirective(name: 'restrictedTo', on: {DirectiveLocation.fieldDefinition})
class RestrictedTo {
  /// The roles allowed to read the field.
  final List<Role> roles;

  /// Applies the directive.
  const RestrictedTo({required this.roles});
}
