import 'dart:io';

import 'package:graphql_schema_generator/graphql_schema_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Writes [pubspec] to a throwaway directory and reads it back.
GeneratorConfig loadFrom(String pubspec) {
  final directory = Directory.systemTemp.createTempSync('gsg_config');
  addTearDown(() => directory.deleteSync(recursive: true));

  final file = File(p.join(directory.path, 'pubspec.yaml'))
    ..writeAsStringSync(pubspec);

  return GeneratorConfig.load(file.path);
}

void main() {
  group('GeneratorConfig.load', () {
    test('falls back to the defaults when the section is absent', () {
      final config = loadFrom('name: acme\n');

      expect(config.packageName, 'acme');
      expect(config.outputPath, 'lib/schema.graphql');
      expect(config.configuredRoots, isEmpty);
      expect(config.exclude, ['lib/**.g.dart']);
      expect(config.skip, isEmpty);
      expect(config.scalars, {'DateTime': 'DateTime'});
    });

    test(
      'reads the roots that are set and leaves out the ones that are not',
      () {
        final config = loadFrom('''
name: acme

graphql_schema_generator:
  roots:
    query: lib/api/queries.dart#Queries
    mutation: ''
''');

        expect(config.configuredRoots, {
          'Query': 'lib/api/queries.dart#Queries',
        });
      },
    );

    test('reads the lists and the scalar map', () {
      final config = loadFrom('''
name: acme

graphql_schema_generator:
  output: build/schema.graphql
  include:
    - lib/models/**.dart
  exclude:
    - lib/**.freezed.dart
  skip:
    - Product.cacheKey
  scalars:
    DateTime: DateTime
    Uri: Url
''');

      expect(config.outputPath, 'build/schema.graphql');
      expect(config.include, ['lib/models/**.dart']);
      expect(config.exclude, ['lib/**.freezed.dart']);
      expect(config.skip, {'Product.cacheKey'});
      expect(config.scalars, {'DateTime': 'DateTime', 'Uri': 'Url'});
    });

    test('refuses a pubspec that is not there', () {
      expect(
        () => GeneratorConfig.load('nowhere/pubspec.yaml'),
        throwsA(isA<ConfigException>()),
      );
    });

    test('refuses a pubspec with no package name', () {
      expect(
        () => loadFrom('description: nameless\n'),
        throwsA(isA<ConfigException>()),
      );
    });
  });
}
