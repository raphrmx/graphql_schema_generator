/// How a Dart name becomes a GraphQL name.
library;

/// The GraphQL type name of the Dart class [className].
///
/// Drops the first prefix in [stripPrefixes] the name starts with, then adds
/// [inputSuffix] when the class is being emitted as an input type. A class
/// whose name already ends with the suffix keeps the name it has, so a
/// `ProductInput` never becomes a `ProductInputInput`.
String graphQLTypeName(
  String className, {
  required bool isInput,
  List<String> stripPrefixes = const [],
  String inputSuffix = 'Input',
}) {
  final prefix = stripPrefixes.firstWhere(
    (p) =>
        p.isNotEmpty && className.startsWith(p) && className.length > p.length,
    orElse: () => '',
  );
  final base = prefix.isEmpty ? className : className.substring(prefix.length);

  if (!isInput || inputSuffix.isEmpty || base.endsWith(inputSuffix)) {
    return base;
  }
  return '$base$inputSuffix';
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
