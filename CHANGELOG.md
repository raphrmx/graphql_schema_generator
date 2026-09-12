## 0.1.0

First release.

- Reads a package's Dart sources and writes the GraphQL schema they describe.
  The sources need no annotation and no GraphQL import: a class is a type, its
  public instance fields are the fields, an enum is an enum.
- The classes named under `roots:` turn their public methods into the fields of
  `Query`, `Mutation` and `Subscription`: the parameters become the arguments,
  the return type becomes the type of the field, and `Future`, `FutureOr` and
  `Stream` are unwrapped.
- A class reached from an argument is emitted as an input type, one reached
  from a return value as an object type, and one reached from both is emitted
  twice. GraphQL keeps object types and input types apart, so a single Dart
  class cannot serve as both under one name.
- A `sealed` class becomes a union of its subtypes. Dart keeps every subtype in
  the declaring library, so the members are read rather than guessed, and a
  nested sealed hierarchy is flattened because GraphQL has no union of unions.
  A union in argument position stops the run.
- A computed getter becomes a field, next to the stored ones. Its description
  and its `@Deprecated` are read from the getter, which is where they live.
- A field with no documentation of its own takes the description of the
  interface or superclass that also declares it, the way a Dart doc comment is
  inherited.
- `///` comments become descriptions and `@Deprecated` becomes `@deprecated`.
- `skip:` leaves a field or an operation out of the schema by name,
  `Product.cacheKey`, so a member stays internal without the Dart changing
  shape. `scalars:` maps a Dart type to a GraphQL scalar by name.
- An abstract class is an interface. A class reaching it through `implements`
  carries `implements` in the schema, and one reaching a class through
  `extends` reads its fields into the type instead. An interface that no object
  type in the schema implements stops the run: a field answering with it could
  never resolve, and GraphQL calls such a schema valid all the same.
- The annotations of `graphql_schema_annotation` say what the Dart cannot.
  `@GraphQLDirective` on a class declares a directive and an instance of that
  class applies it, arguments included; applying one where its locations do not
  allow it, or twice when it is not repeatable, stops the run.
  `@GraphQLScalar` carries a type to a scalar, `@GraphQLSkip` keeps a member
  out of the schema, and `@GraphQLInterface` publishes an abstract class
  reached through `extends`.
- A type is called what its class is called, and a field what its field is
  called. The only name the generator invents is the `Input` suffix. Nothing
  about naming is configurable, so a schema fed back to a generator going the
  other way gives back the classes it started from.
- The layout is byte for byte what `printSchema` from `graphql-js` writes. The
  order of the definitions is not: directives first, then the roots, then the
  rest by name, which gives a file that only changes when the schema does.
