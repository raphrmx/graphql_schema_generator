import 'package:graphql_schema_annotation/graphql_schema_annotation.dart';

/// The stock keeping unit, as a type of its own rather than a bare string.
// An extension type is a name over another type, and the generator writes the
// type underneath, `String`. The annotation is what carries it to `ID`.
@GraphQLScalar('ID')
extension type const Sku(String value) {}
