/// How a Dart name becomes a GraphQL name.
library;

/// Added to the name of a class emitted as an input type.
///
/// Not a setting. A GraphQL schema cannot give an object type and an input
/// type the same name, so a class read on both sides has to be emitted twice
/// under two names, and one fixed rule is what lets a reader of the schema, or
/// a generator going the other way, work out which Dart class it came from.
const String inputSuffix = 'Input';

/// The GraphQL type name of the Dart class [className].
///
/// The name is the one the class already carries, so the schema and the code
/// call the same thing by the same name, and a generator reading the schema
/// back gets the class it started from. In input position it gains
/// [inputSuffix], unless it already ends with it, so a `ProductInput` never
/// becomes a `ProductInputInput`.
String graphQLTypeName(String className, {required bool isInput}) {
  if (!isInput || className.endsWith(inputSuffix)) return className;
  return '$className$inputSuffix';
}

/// The text of a Dart documentation comment, without its `///` markers.
///
/// Returns null when [comment] is null or holds nothing but markers, so an
/// empty doc comment is the same as no doc comment at all.
String? documentationText(String? comment) {
  if (comment == null) return null;

  final lines = comment
      .split('\n')
      .map((line) => line.replaceFirst(RegExp(r'^\s*///\s?'), ''))
      .map((line) => line.replaceFirst(RegExp(r'^\s*\*\s?'), ''))
      .toList();

  while (lines.isNotEmpty && lines.first.trim().isEmpty) {
    lines.removeAt(0);
  }
  while (lines.isNotEmpty && lines.last.trim().isEmpty) {
    lines.removeLast();
  }

  final text = lines.join('\n').trimRight();
  return text.isEmpty ? null : text;
}
