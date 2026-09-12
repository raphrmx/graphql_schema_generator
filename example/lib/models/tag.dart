import 'package:acme_catalogue/models/listable.dart';

/// A label a product can be filed under.
// Read back inside a product and written inside a draft, so the generator
// emits it twice: once as a type and once as an input. A GraphQL input type
// implements nothing, so `implements Listable` reaches the type alone.
class Tag implements Listable {
  /// The machine-readable name, unique across the catalogue.
  final String slug;

  @override
  final String label;

  const Tag({required this.slug, required this.label});
}
