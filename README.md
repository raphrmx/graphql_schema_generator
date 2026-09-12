<a alt="ComApps Logo" href="https://comapps.be" target="_blank" rel="noreferrer"><img src="https://www.comapps.be/wp-content/uploads/2026/09/CompleteLogoHorizontalMini.png" style="margin: 15px"></a>

# GraphQL Schema Generator

[![Build](https://img.shields.io/github/actions/workflow/status/raphrmx/graphql_schema_generator/ci.yml?branch=main&label=build)](https://github.com/raphrmx/graphql_schema_generator/actions/workflows/ci.yml)
[![Pub Version](https://img.shields.io/pub/v/graphql_schema_generator?color=blue)](https://pub.dev/packages/graphql_schema_generator)
[![Maintainer](https://img.shields.io/badge/Maintainer-Raphael_Vrient-purple)](https://comapps.be)
[![License](https://img.shields.io/badge/Licence-MIT-blue)](/LICENSE)
![Maintenance](https://img.shields.io/badge/Maintained-yes-success)
![Platforms](https://img.shields.io/badge/Platforms-Android,_iOS,_macOS,_Windows,_Linux-22375C.svg)

Writes the `.graphql` schema your Dart classes already describe. It reads the
sources, so there is no server to start and no introspection query to send.

Your models say nothing about GraphQL: no annotation, no base class, no
import. A class is a type, its public instance fields are the fields, an enum
is an enum, and the classes you name as roots turn their public methods into
operations. The types, the inputs, the enums, the arguments, the nullability
and the documentation all come from the code.

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

A companion package of annotations covers the few things Dart has no way of
saying. Nothing before [Annotations](#annotations) needs it.

## Install

The generator is a command that reads your sources and ships with nothing, so
it goes in `dev_dependencies`.

```yaml
dev_dependencies:
  graphql_schema_generator: ^0.1.0
```

Name your root classes in the same `pubspec.yaml`. A root is a class whose
public methods you want as operations.

```yaml
graphql_schema_generator:
  roots:
    query: lib/api/queries.dart#Queries
    mutation: lib/api/mutations.dart#Mutations
    subscription: lib/api/subscriptions.dart#Subscriptions
```

Then run it from the root of that package:

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
| A class that `implements` one | `implements` on the type |
| A class that `extends` one | its fields, read into the type |
| A `sealed` class | `union` of its subtypes |
| An `enum` | `enum`, with the Dart constant names |
| A public instance field, stored or computed | a field of that type |
| An `extension type` | the type underneath, or a scalar you name |
| `String`, `int`, `double`, `num`, `bool` | `String`, `Int`, `Float`, `Float`, `Boolean` |
| `List<T>`, `Set<T>`, `Iterable<T>` | `[T]` |
| A non-nullable type | `T!` |
| `DateTime`, and whatever else you map | a custom `scalar` |
| A `///` documentation comment | a description |
| `@Deprecated('why')` | `@deprecated(reason: "why")` |
| A public method of a root class | a field of `Query`, `Mutation` or `Subscription` |
| Its parameters | the arguments of that field |
| `Future<T>`, `FutureOr<T>`, `Stream<T>` | `T` |

A class used on both sides is emitted twice, once as a type and once as an
input, since GraphQL keeps object types and input types apart.

Three rows of that table come from the language rather than from anything you
configure.

- A `sealed` class is already a union. Dart keeps every subtype in the
  declaring library, so the members are read rather than guessed.
- `implements` is already a promise about shape, which is what a GraphQL
  interface is. `extends` is implementation reuse, so a superclass hands its
  fields to the type and names nothing in the schema.
- An `extension type` is a name over another type, so the schema carries the
  type underneath unless you name a scalar for it.

Naming a scalar is how a field reaches `ID`:

```dart
@GraphQLScalar('ID')
extension type const Sku(String value) {}
```

For a type you do not own, `scalars:` in `pubspec.yaml` maps it by name
instead.

## Annotations

Two things in a schema have no Dart for the generator to read: a directive on
a field, and the scalar an `extension type` stands for. Both come from a
companion package that your models import and that the generator itself never
needs.

```yaml
dependencies:
  graphql_schema_annotation: ^0.1.0
```

| Annotation | What it does |
| --- | --- |
| `@GraphQLDirective` | Declares a class as a GraphQL directive, which you apply by writing an instance of it |
| `@GraphQLScalar` | Sends a type to a named scalar, such as `ID` |
| `@GraphQLSkip` | Keeps a member out of the schema, and follows it when you rename it |
| `@GraphQLInterface` | Publishes an abstract class that a type reaches through `extends` |

A directive is a class: the class is the declaration, and an instance of it is
an application.

```dart
/// The value holds between [min] and [max] characters.
@GraphQLDirective(name: 'length', on: {DirectiveLocation.inputFieldDefinition})
class Length {
  final int min;
  final int max;

  const Length({required this.max, this.min = 1});
}

class ProductDraft {
  @Length(max: 120)
  final String label;
}
```

```graphql
"""The value holds between [min] and [max] characters."""
directive @length(min: Int! = 1, max: Int!) on INPUT_FIELD_DEFINITION

input ProductDraftInput {
  label: String! @length(min: 1, max: 120)
}
```

The fields of the class are the arguments of the directive, and their values
come from the call that applies it. Applying a directive outside the locations
its `on` lists stops the run, and so does applying one twice unless the
declaration says `repeatable: true`.

See
[graphql_schema_annotation](https://pub.dev/packages/graphql_schema_annotation)
for the whole vocabulary.

## Naming

A type is called what its class is called. `AcmeProduct` is `AcmeProduct` in
the schema, not `Product`, and a field is called what the Dart field is
called. None of this is configurable, so a generator reading the schema back
hands you the classes you started from.

The one name the generator invents is the `Input` suffix, and only for a class
it reads in argument position. Two Dart classes that would land on the same
GraphQL name stop the run rather than overwrite one another.

That suffix is also the one place where the round trip with
[graphql_openapi_codegen](https://pub.dev/packages/graphql_openapi_codegen),
which goes the other way, is not an identity. A `ProductDraft` written here
reads back as a `ProductDraftInput`, since nothing in the SDL records that the
suffix was added.

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
  skip: []                          # members left out, as ClassName.member
  scalars:                          # Dart type -> GraphQL scalar
    DateTime: DateTime
```

Use `include` when you have no roots and only want the shape of your data
written down, or when a type has to be in the schema although no operation
mentions it yet.

Use `skip` to keep a field or an operation out of the schema without changing
your Dart. It names members, `Product.cacheKey` or `Queries.debugDump`, and an
inherited one can be named after either class. On your own code prefer
`@GraphQLSkip()` on the member, which survives a rename where the list goes
stale in silence.

## The order of the file

Directives first, sorted by name. Then `Query`, `Mutation` and `Subscription`.
Then every other type, sorted by name. A schema read from Dart sources has no
definition order to preserve, and a stable one is what lets a build fail on a
real change rather than on a reshuffle.

Everything else about the layout is what `printSchema` from `graphql-js`
writes, down to the byte: block string descriptions, a blank line before a
described field, arguments on one line unless one of them is described,
built-in scalars left out.

## What it refuses

An unreadable type stops the run and names the field, rather than quietly
leaving it out of the schema. Three cases stop it.

- `Map`, `dynamic` and `Object` have no GraphQL shape. Map the Dart type to a
  scalar under `scalars:`, name the member under `skip:`, or give it a class.
- An interface nothing implements. A type reaches an interface through
  `implements`, not through `extends`, so a class that only extends an
  abstract one leaves it without an implementation, and a field answering with
  it could never resolve.
- A union in argument position. A sealed class read from an argument has no
  GraphQL equivalent there.

## Reading the source instead of a running server

The usual way to get an SDL file out of a Dart server is to start it, send an
introspection query and print what comes back. That needs a running endpoint,
a credential to reach it, and an endpoint that still answers introspection
where you are pointing. It also drops what introspection does not carry, the
directives applied to your fields among them.

This one reads the source, so it runs in CI with nothing started, on a branch
that does not boot, and on a server you have not written yet.

## The example

`example/` is a real package, and CI generates it on every run and fails on a
diff. Read `example/lib/models` and `example/lib/api`, then
`example/lib/schema.graphql` for what came out of them.

## Licence

MIT. See [LICENSE](LICENSE).
