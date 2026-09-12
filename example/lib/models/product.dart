import 'package:acme_catalogue/models/availability.dart';
import 'package:acme_catalogue/models/tag.dart';
import 'package:json_annotation/json_annotation.dart';

part 'product.g.dart';

/// A product on sale.
@JsonSerializable()
class Product {
  /// The stock keeping unit. Unique across the catalogue.
  final String sku;

  /// The name shown to a customer.
  final String label;

  /// The price in cents, to keep the wire format free of floating point.
  @JsonKey(name: 'price_cents')
  final int priceCents;

  /// Whether the product can be ordered right now.
  final Availability availability;

  /// The labels the product is filed under.
  final List<Tag> tags;

  /// When the product first went on sale, or null while it is a draft.
  final DateTime? releasedAt;

  /// The old free-form category, kept until the last importer is migrated.
  @Deprecated('Use tags instead.')
  final String? category;

  const Product({
    required this.sku,
    required this.label,
    required this.priceCents,
    required this.availability,
    required this.tags,
    this.releasedAt,
    @Deprecated('Use tags instead.') this.category,
  });

  /// Reads a product from its JSON form.
  factory Product.fromJson(Map<String, dynamic> json) =>
      _$ProductFromJson(json);

  /// Writes the product to its JSON form.
  Map<String, dynamic> toJson() => _$ProductToJson(this);
}
