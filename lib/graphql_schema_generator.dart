/// Generates a GraphQL schema from plain Dart sources.
///
/// The entry point is the `graphql_schema_generator` executable:
///
/// ```bash
/// dart run graphql_schema_generator
/// ```
///
/// It reads its settings from the `graphql_schema_generator:` section of the
/// package's `pubspec.yaml`. See [GeneratorConfig] for what that section holds,
/// [run] to drive it from Dart, and [generate] to get the schema back instead
/// of writing it to a file.
library;

export 'src/config.dart' show ConfigException, GeneratorConfig;
export 'src/model.dart';
export 'src/printer.dart'
    show
        defaultDeprecationReason,
        printBlockString,
        printSchema,
        printTypeRef,
        specifiedDirectiveNames,
        specifiedScalarNames;
export 'src/reader.dart' show SchemaReadException, SchemaReader;
export 'src/runner.dart' show generate, run;
