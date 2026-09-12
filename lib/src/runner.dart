/// The generation pipeline.
///
/// Reads the configuration from `pubspec.yaml`, reads the Dart sources it
/// names, prints the schema and writes it where the configuration says.
library;

import 'dart:io';

import 'package:graphql_schema_generator/src/config.dart';
import 'package:graphql_schema_generator/src/enums.dart';
import 'package:graphql_schema_generator/src/log.dart';
import 'package:graphql_schema_generator/src/model.dart';
import 'package:graphql_schema_generator/src/printer.dart';
import 'package:graphql_schema_generator/src/reader.dart';
import 'package:path/path.dart' as p;

/// Runs the generator over the package in the current directory.
///
/// Exits with a non-zero code when the sources cannot be read, so a build step
/// fails rather than leaving a stale schema in place.
Future<void> run(List<String> arguments) async {
  final root = arguments.isEmpty ? Directory.current.path : arguments.first;

  try {
    final config = GeneratorConfig.load(p.join(root, 'pubspec.yaml'));
    final schema = await generate(config, packageRoot: root);
    final sdl = printSchema(schema);

    final output = File(p.join(root, config.outputPath));
    output.parent.createSync(recursive: true);
    output.writeAsStringSync(sdl);

    _report(config, schema);
  } on SchemaReadException catch (error) {
    logMessage('\n${error.message}\n', type: MessageType.error);
    exit(1);
  } on ConfigException catch (error) {
    logMessage('\n${error.message}\n', type: MessageType.error);
    exit(1);
  }
}

/// Builds the schema [config] describes, without writing anything.
Future<SdlSchema> generate(
  GeneratorConfig config, {
  required String packageRoot,
}) => SchemaReader(config, packageRoot: packageRoot).read();

void _report(GeneratorConfig config, SdlSchema schema) {
  final counts = <String, int>{
    'type': schema.definitions
        .whereType<SdlObject>()
        .where((d) => !d.isInterface)
        .length,
    'interface': schema.definitions
        .whereType<SdlObject>()
        .where((d) => d.isInterface)
        .length,
    'input': schema.definitions.whereType<SdlInputObject>().length,
    'enum': schema.definitions.whereType<SdlEnum>().length,
    'union': schema.definitions.whereType<SdlUnion>().length,
    'scalar': schema.definitions.whereType<SdlScalar>().length,
  };

  final width = counts.keys
      .map((k) => k.length)
      .reduce((a, b) => a > b ? a : b);

  logMessage('\n===== ${config.outputPath} =====');
  for (final entry in counts.entries) {
    logMessage(
      '${'${entry.key}:'.padRight(width + 2)}${entry.value}',
      type: MessageType.info,
    );
  }
  logMessage('');
  logMessage(
    'Schema written to ${config.outputPath}',
    type: MessageType.success,
  );
  logMessage('');
}
