# The worked example

A catalogue, written as plain Dart. Four files carry an annotation; the rest
mention nothing about GraphQL.

```
lib/directives.dart            three directives, declared as classes
lib/models/availability.dart   an enum, one value deprecated
lib/models/listable.dart       an abstract class marked as an interface
lib/models/product.dart        a type, with a deprecated field and a skipped one
lib/models/product_draft.dart  only ever passed in, so it becomes an input
lib/models/product_filter.dart the same, with defaults the schema carries over
lib/models/role.dart           an enum, read back as a directive argument
lib/models/tag.dart            read and written, so it becomes both
lib/models/search_hit.dart     a sealed class, so it becomes a union
lib/models/sku.dart            an extension type, carried to the ID scalar
lib/api/queries.dart           the Query root, one argument carrying a directive
lib/api/mutations.dart         the Mutation root
lib/api/subscriptions.dart     the Subscription root, returning streams
lib/schema.graphql             what came out
```

Run it:

```bash
dart pub get
dart run graphql_schema_generator
```

## Result

[lib/schema.graphql](lib/schema.graphql)
