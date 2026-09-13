## 0.1.1

- Corrects the Dart floor to 3.9, and accepts `analyzer` from 12.0.0. Every
  `analyzer` 14.x requires Dart 3.11, so the `^3.8.0` of 0.1.0 promised an
  install that could not resolve on 3.8, 3.9 or 3.10. Widening the constraint
  makes the declared floor true and reaches two minor versions below what 14.x
  allows. Below `analyzer` 12 the element model the reader walks does not
  exist.
- No change to what the generator reads or writes.

## 0.1.0

First release.

- Reads a package's Dart sources and writes the GraphQL schema they describe.
  The sources need no annotation and no GraphQL import: a class is a type, its
  public instance fields are the fields, an enum is an enum.
- The classes named under `roots:` turn their public methods into the fields of
  `Query`, `Mutation` and `Subscription`. The parameters become the arguments,
  the return type becomes the type of the field, and `Future`, `FutureOr` and
  `Stream` are unwrapped.
- A class reached from an argument is emitted as an input type, one reached
  from a return value as an object type, and one reached from both is emitted
  twice. GraphQL keeps object types and input types apart, so a single Dart
  class cannot serve as both under one name.
- A `sealed` class becomes a union of its subtypes. Dart keeps every subtype in
  the declaring library, so the members are read rather than guessed, and a
  nested sealed hierarchy is flattened because GraphQL has no union of unions.
- An abstract class is an interface. A class reaching it through `implements`
  carries `implements` in the schema, and one reaching it through `extends`
  reads its fields into the type instead.
- An `extension type` carries the type underneath into the schema, unless a
  scalar is named for it.
- A computed getter becomes a field, next to the stored ones. Its description
  and its `@Deprecated` are read from the getter, which is where they live.
- A field with no documentation of its own takes the description of the
  interface or superclass that also declares it, the way a Dart doc comment is
  inherited.
- `///` comments become descriptions and `@Deprecated` becomes `@deprecated`.
- Settings live in the `graphql_schema_generator:` section of `pubspec.yaml`.
  `output:` says where the file goes, `roots:` names the operation roots,
  `include:` brings in files whose types no operation reaches and `exclude:`
  filters that list, `skip:` leaves a member out by name, and `scalars:` maps a
  Dart type to a GraphQL scalar.
- The annotations of `graphql_schema_annotation` say what the Dart cannot.
  `@GraphQLDirective` on a class declares a directive, and an instance of that
  class applies it with its arguments. `@GraphQLScalar` carries a type to a
  scalar, `@GraphQLSkip` keeps a member out of the schema, and
  `@GraphQLInterface` publishes an abstract class reached through `extends`.
- A type is called what its class is called, and a field what its field is
  called. The only name the generator invents is the `Input` suffix. Nothing
  about naming is configurable, so a schema fed back to a generator going the
  other way gives back the classes it started from.
- The run stops, naming the place, rather than writing a schema that could not
  work. A `Map`, a `dynamic` or an `Object` field stops it, so do a type with
  no field, an interface no object type implements, a union in argument
  position, two Dart classes landing on one GraphQL name, and a directive
  applied outside the locations it declares or twice when it is not
  repeatable. The sources are read resolved, so the package has to analyse
  cleanly first.
- The layout is what `printSchema` from `graphql-js` writes, down to the byte.
  Applied directives are the one exception, because `printSchema` does not
  carry them. Those follow the `graphql-js` document printer instead.
- The order of the definitions is this package's own: directives first, then
  the roots, then the rest by name, which gives a file that changes only when
  the schema does.
