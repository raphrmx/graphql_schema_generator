import 'package:acme_catalogue/models/availability.dart';

/// Narrows a product listing.
///
/// Only ever passed to a method, so the generator emits it as an input type
/// and never as an object type.
class ProductFilter {
  /// Keeps the products whose label contains this text.
  final String? labelContains;

  /// Keeps the products in this state.
  final Availability? availability;

  /// Keeps the products filed under every one of these tags.
  final List<String> tagSlugs;

  const ProductFilter({
    this.labelContains,
    this.availability,
    this.tagSlugs = const [],
  });
}
