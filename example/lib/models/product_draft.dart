import 'package:acme_catalogue/directives.dart';
import 'package:acme_catalogue/models/availability.dart';
import 'package:acme_catalogue/models/sku.dart';
import 'package:acme_catalogue/models/tag.dart';

/// The full state of a product, as the caller wants it stored.
class ProductDraft {
  /// The stock keeping unit the product is stored under.
  final Sku sku;

  /// The name shown to a customer.
  @Length(max: 120)
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
  }) : assert(
         label.length >= 1 && label.length <= 120,
         'A label holds between 1 and 120 characters.',
       );
}
