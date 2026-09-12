import 'package:json_annotation/json_annotation.dart';

part 'tag.g.dart';

/// A label a product can be filed under.
///
/// Read back inside a product and written inside a draft, so the generator
/// emits it twice: once as a type and once as an input.
@JsonSerializable()
class Tag {
  /// The machine-readable name, unique across the catalogue.
  final String slug;

  /// The name shown to a customer.
  @JsonKey(name: 'display_label')
  final String label;

  const Tag({required this.slug, required this.label});

  /// Reads a tag from its JSON form.
  factory Tag.fromJson(Map<String, dynamic> json) => _$TagFromJson(json);

  /// Writes the tag to its JSON form.
  Map<String, dynamic> toJson() => _$TagToJson(this);
}
