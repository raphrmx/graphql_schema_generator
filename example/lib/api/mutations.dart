import 'package:acme_catalogue/directives.dart';
import 'package:acme_catalogue/models/product.dart';
import 'package:acme_catalogue/models/product_draft.dart';
import 'package:acme_catalogue/models/role.dart';
import 'package:acme_catalogue/models/sku.dart';
import 'package:acme_catalogue/models/tag.dart';

/// What the catalogue can be told.
class Mutations {
  /// Creates a product, or replaces the one already carrying that SKU.
  Future<Product> upsertProduct(ProductDraft draft) async =>
      throw UnimplementedError();

  /// Files an existing product under one more tag.
  Future<Product> tagProduct(Sku sku, Tag tag) async =>
      throw UnimplementedError();

  /// Removes a product from the catalogue.
  @Deprecated('Set availability to outOfStock instead.')
  @RestrictedTo(roles: [Role.staff])
  Future<bool> deleteProduct(Sku sku) async => false;
}
