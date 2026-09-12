import 'dart:io';

import 'package:yaml/yaml.dart';

/// Thrown when the configuration cannot be read.
class ConfigException implements Exception {
  /// What is wrong with the configuration.
  final String message;

  /// Creates an exception carrying [message].
  ConfigException(this.message);

  @override
  String toString() => message;
}

/// Everything the generator needs to know about the package it reads.
///
/// Read from the `graphql_schema_generator:` section of `pubspec.yaml`, next to
/// the package name it already has to read. Every entry is optional; the
/// fallbacks describe a package with no root classes and no extra types, which
/// produces an empty schema, so a project says what it exposes rather than the
/// tool guessing.
///
/// ```yaml
/// graphql_schema_generator:
///   output: lib/schema.graphql        # where the SDL is written
///   roots:                            # one Dart class per operation root
///     query: lib/api/queries.dart#Queries
///     mutation: lib/api/mutations.dart#Mutations
///     subscription: ''
///   include:                          # extra types, whether or not a root
///     - lib/models/**.dart            # reaches them
///   exclude:
///     - lib/**.g.dart
///   skip:                             # members left out of the schema
///     - Product.internalCache
///   scalars:                          # Dart type -> GraphQL scalar
///     DateTime: DateTime
/// ```
class GeneratorConfig {
  /// The name of the package, from `pubspec.yaml`.
  final String packageName;

  /// Where the SDL is written, relative to the package root.
  final String outputPath;

  /// The class whose public methods become the fields of `Query`, written as
  /// `path/to/file.dart#ClassName`. Empty means the schema has no query root.
  final String queryRoot;

  /// The class whose public methods become the fields of `Mutation`. Empty
  /// means the schema has no mutation root.
  final String mutationRoot;

  /// The class whose public methods become the fields of `Subscription`.
  /// Empty means the schema has no subscription root.
  final String subscriptionRoot;

  /// Globs of files whose public classes and enums are emitted whether or not
  /// a root reaches them.
  final List<String> include;

  /// Globs of files never read. Generated parts are excluded by default: they
  /// hold no model of their own, and reading them doubles every type.
  final List<String> exclude;

  /// Members left out of the schema, written `ClassName.memberName`.
  ///
  /// The way to keep a field or an operation out without changing the Dart.
  /// An inherited member can be named after the class that declares it or
  /// after the one that exposes it.
  final Set<String> skip;

  /// Dart types mapped to the GraphQL scalar that carries them, beyond the
  /// ones the language and the specification agree on.
  final Map<String, String> scalars;

  const GeneratorConfig({
    required this.packageName,
    this.outputPath = 'lib/schema.graphql',
    this.queryRoot = '',
    this.mutationRoot = '',
    this.subscriptionRoot = '',
    this.include = const [],
    this.exclude = const ['lib/**.g.dart'],
    this.skip = const {},
    this.scalars = const {'DateTime': 'DateTime'},
  });

  /// Reads the configuration from [pubspecPath].
  ///
  /// Throws when the package name cannot be read: the generator resolves Dart
  /// sources against the package it is run from, so it has to be run from that
  /// package's root.
  factory GeneratorConfig.load([String pubspecPath = 'pubspec.yaml']) {
    final file = File(pubspecPath);
    if (!file.existsSync()) {
      throw ConfigException(
        'No $pubspecPath here. The generator must be run from the root of the '
        'package it reads.',
      );
    }

    final pubspec = loadYaml(file.readAsStringSync());
    final name = pubspec is YamlMap ? pubspec['name'] : null;
    if (name is! String || name.isEmpty) {
      throw ConfigException('$pubspecPath declares no package name.');
    }

    final section = pubspec is YamlMap
        ? pubspec['graphql_schema_generator']
        : null;
    if (section is! YamlMap) return GeneratorConfig(packageName: name);

    const fallback = GeneratorConfig(packageName: '');

    final roots = section['roots'];
    final Map<dynamic, dynamic> root = roots is YamlMap
        ? roots
        : const <dynamic, dynamic>{};

    return GeneratorConfig(
      packageName: name,
      outputPath: _string(section, 'output', fallback.outputPath),
      queryRoot: _string(root, 'query', fallback.queryRoot),
      mutationRoot: _string(root, 'mutation', fallback.mutationRoot),
      subscriptionRoot: _string(
        root,
        'subscription',
        fallback.subscriptionRoot,
      ),
      include: _stringList(section, 'include', fallback.include),
      exclude: _stringList(section, 'exclude', fallback.exclude),
      skip: _stringList(section, 'skip', fallback.skip.toList()).toSet(),
      scalars: _stringMap(section, 'scalars', fallback.scalars),
    );
  }

  /// The roots that are configured, paired with the type name each one takes.
  Map<String, String> get configuredRoots => {
    if (queryRoot.isNotEmpty) 'Query': queryRoot,
    if (mutationRoot.isNotEmpty) 'Mutation': mutationRoot,
    if (subscriptionRoot.isNotEmpty) 'Subscription': subscriptionRoot,
  };
}

/// A blank value means "not set", and falls back.
String _string(Map<dynamic, dynamic> from, String key, String orElse) {
  final value = from[key];
  return value is String && value.trim().isNotEmpty ? value.trim() : orElse;
}

List<String> _stringList(
  Map<dynamic, dynamic> from,
  String key,
  List<String> orElse,
) {
  final value = from[key];
  if (value is! YamlList) return orElse;
  return value.whereType<String>().map((e) => e.trim()).toList();
}

Map<String, String> _stringMap(
  Map<dynamic, dynamic> from,
  String key,
  Map<String, String> orElse,
) {
  final value = from[key];
  if (value is! YamlMap) return orElse;

  final read = <String, String>{};
  for (final entry in value.entries) {
    final k = entry.key;
    final v = entry.value;
    if (k is String && v is String) read[k.trim()] = v.trim();
  }
  return read.isEmpty ? orElse : read;
}
