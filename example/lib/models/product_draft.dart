import 'package:acme_catalogue/models/availability.dart';
import 'package:acme_catalogue/models/tag.dart';

/// The full state of a product, as the caller wants it stored.
class ProductDraft {
  /// The stock keeping unit the product is stored under.
  final String sku;

  /// The name shown to a customer.
  final String label;

  /// The price in cents.
  final int priceCents;

  /// Whether the product can be ordered once stored.
  final Availability availability;

  /// The labels to file the product under.
  final List<Tag> tags;

  const ProductDraft({
    required this.sku,
    required this.label,
    required this.priceCents,
    this.availability = Availability.inStock,
    this.tags = const [],
  });
}
