# The worked example

A catalogue, written as plain Dart. Nothing here imports a GraphQL package.

```
lib/models/availability.dart   an enum, one value deprecated
lib/models/product.dart        a type, with a renamed field and a deprecated one
lib/models/product_draft.dart  only ever passed in, so it becomes an input
lib/models/product_filter.dart the same, with defaults the schema carries over
lib/models/tag.dart            read and written, so it becomes both
lib/api/queries.dart           the Query root
lib/api/mutations.dart         the Mutation root
lib/schema.graphql             what came out
```

Run it:

```bash
dart pub get
dart run build_runner build --delete-conflicting-outputs
dart run graphql_schema_generator
```

The first command writes the `json_serializable` parts, which are not in the
repository. The generator reads resolved sources, so the package has to compile
before it runs.

`lib/schema.graphql` is committed, and CI regenerates it and fails on a diff.
