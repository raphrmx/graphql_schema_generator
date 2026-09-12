## 0.1.0

First release.

- Reads a package's Dart sources and writes the GraphQL schema they describe.
  The sources carry no annotation and no GraphQL import: a class is a type, its
  public instance fields are the fields, an enum is an enum.
- The classes named under `roots:` turn their public methods into the fields of
  `Query`, `Mutation` and `Subscription`: the parameters become the arguments,
  the return type becomes the type of the field, and `Future`, `FutureOr` and
  `Stream` are unwrapped.
- A class reached from an argument is emitted as an input type, one reached
  from a return value as an object type, and one reached from both is emitted
  twice. GraphQL keeps object types and input types apart, so a single Dart
  class cannot serve as both under one name.
- `///` comments become descriptions, `@Deprecated` becomes `@deprecated`, and
  `@JsonKey(name:)` renames a field, because that annotation already says what
  the field is called on the wire.
- The layout is byte for byte what `printSchema` from `graphql-js` writes. The
  order of the definitions is not: roots first, then the rest by name, which
  gives a file that only changes when the schema does.
