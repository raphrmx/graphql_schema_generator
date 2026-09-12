import 'package:acme_catalogue/directives.dart';
import 'package:acme_catalogue/models/availability.dart';
import 'package:acme_catalogue/models/listable.dart';
import 'package:acme_catalogue/models/sku.dart';
import 'package:acme_catalogue/models/tag.dart';
import 'package:graphql_schema_annotation/graphql_schema_annotation.dart';

/// A product on sale.
@Audited()
class Product implements Listable {
  /// The stock keeping unit. Unique across the catalogue.
  final Sku sku;

  @override
  final String label;

  /// The price in cents, to keep the wire format free of floating point.
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

  /// Where the rendered page for this product is cached.
  // Internal to the server, and kept out of the schema by the annotation,
  // which follows the field when it is renamed.
  @GraphQLSkip()
  final String cacheKey;

  const Product({
    required this.sku,
    required this.label,
    required this.priceCents,
    required this.availability,
    required this.tags,
    required this.cacheKey,
    this.releasedAt,
    @Deprecated('Use tags instead.') this.category,
  });

  /// The price in whole euros, rounded down.
  // A computed getter, not a stored field, and a field of the type all the
  // same.
  int get priceEuros => priceCents ~/ 100;
}
