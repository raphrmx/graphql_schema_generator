# GraphQL Schema Generator

[![Build](https://img.shields.io/github/actions/workflow/status/raphrmx/graphql_schema_generator/ci.yml?branch=main&label=build)](https://github.com/raphrmx/graphql_schema_generator/actions/workflows/ci.yml)
[![Pub Version](https://img.shields.io/pub/v/graphql_schema_generator?color=blue)](https://pub.dev/packages/graphql_schema_generator)
[![License](https://img.shields.io/badge/Licence-MIT-blue)](LICENSE)

## Your Dart classes are already the schema

You have model classes and a couple of service classes. Run this and you have
the `.graphql` file that describes them: the types, the inputs, the enums, the
arguments, the nullability and the documentation, all read from the code.

Nothing in your sources mentions GraphQL. No annotation, no base class, no
import. A class is a type, its public fields are the fields, an enum is an
enum, and the classes you name as roots turn their methods into operations.

```dart
/// A product on sale.
class Product {
  /// The stock keeping unit. Unique across the catalogue.
  final String sku;
  final List<Tag> tags;
  final DateTime? releasedAt;
}

class Queries {
  /// Reads one product, or null when the catalogue does not hold it.
  Future<Product?> product(String sku) async => ...;
}
```

```graphql
type Query {
  """Reads one product, or null when the catalogue does not hold it."""
  product(sku: String!): Product
}

"""A product on sale."""
type Product {
  """The stock keeping unit. Unique across the catalogue."""
  sku: String!
  tags: [Tag!]!
  releasedAt: DateTime
}
```

### Why this one and not an introspection dump

The usual way to get an SDL file out of a Dart server is to start it, send it
an introspection query and print what comes back. That needs a running
endpoint, a credential to reach it, and an endpoint that still answers
introspection in the environment you are pointing at. It also loses everything
introspection does not carry.

This one reads the source. It runs in CI with nothing started, on a branch that
does not boot, and on a server you have not written yet.

## Getting started

Add it as a development dependency:

```yaml
dev_dependencies:
  graphql_schema_generator: ^0.1.0
```

Tell it where the roots are, in the same `pubspec.yaml`:

```yaml
graphql_schema_generator:
  roots:
    query: lib/api/queries.dart#Queries
    mutation: lib/api/mutations.dart#Mutations
```

Run it from the root of that package:

```bash
dart run graphql_schema_generator
```

The schema lands in `lib/schema.graphql`.

## What becomes what

| Dart | GraphQL |
| --- | --- |
| A class returned by an operation, directly or through a field | `type` |
| A class passed to an operation, directly or through a field | `input`, named with the `Input` suffix |
| An abstract class | `interface` |
| An `enum` | `enum`, with the Dart constant names |
| `String`, `int`, `double`, `num`, `bool` | `String`, `Int`, `Float`, `Float`, `Boolean` |
| `List<T>`, `Set<T>`, `Iterable<T>` | `[T]` |
| A non-nullable type | `T!` |
| `DateTime`, and whatever else you map | a custom `scalar` |
| A `///` documentation comment | a description |
| `@Deprecated('why')` | `@deprecated(reason: "why")` |
| `@JsonKey(name: 'x')` | the field is called `x` |
| A public method of a root class | a field of `Query`, `Mutation` or `Subscription` |
| Its parameters | the arguments of that field |
| `Future<T>`, `FutureOr<T>`, `Stream<T>` | `T` |

A class used on both sides is emitted twice, as a type and as an input, because
GraphQL keeps the two apart.

## Configuration

Every entry is optional. These are the defaults.

```yaml
graphql_schema_generator:
  output: lib/schema.graphql        # where the SDL is written
  roots:                            # one Dart class per operation root
    query: ''
    mutation: ''
    subscription: ''
  include: []                       # extra types, whether or not a root
                                    # reaches them, as globs
  exclude:
    - lib/**.g.dart
  input_suffix: Input               # added to a class used as an argument
  strip_class_prefixes: []          # dropped from the front of a type name
  honour_json_key: true             # @JsonKey(name:) renames a field
  scalars:                          # Dart type -> GraphQL scalar
    DateTime: DateTime
```

`include` is what you want when you have no roots and only want the shape of
your data written down, or when a type has to be in the schema although no
operation mentions it yet.

## The order of the file

Directives first, sorted by name. Then `Query`, `Mutation` and `Subscription`.
Then every other type, sorted by name.

A schema read from Dart sources has no natural definition order to preserve,
and a stable one is what lets a build fail on a real change rather than on a
reshuffle. Everything else about the layout is what `printSchema` from
`graphql-js` writes, down to the byte: block string descriptions, a blank line
before a described field, arguments on one line unless one of them is
described, built-in scalars left out.

## What it will not do

- **Directives.** A plain Dart class has nowhere to say `@auth` or
  `@_skuFormat`, so the generator never invents one.
- **Unions.** There is no Dart shape it could read one from without an
  annotation, which is the thing this package is here to avoid. The printer
  knows how to write one, so a future version can grow the reader half.
- **Getters.** Only public instance fields become fields.
- **`Map`, `dynamic`, `Object`.** They have no GraphQL shape. Map the Dart type
  to a scalar under `scalars:`, or keep it out of the schema.

An unreadable type stops the run and names the field, rather than quietly
leaving it out of the schema.

## The example

`example/` is a real package, and CI generates it on every run and fails on a
diff. Read `example/lib/models` and `example/lib/api`, then
`example/lib/schema.graphql` for what came out of them.

## Licence

MIT. See [LICENSE](LICENSE).
