import 'package:acme_catalogue/models/product.dart';
import 'package:acme_catalogue/models/product_draft.dart';
import 'package:acme_catalogue/models/tag.dart';

/// What the catalogue can be told.
class Mutations {
  /// Creates a product, or replaces the one already carrying that SKU.
  Future<Product> upsertProduct(ProductDraft draft) async =>
      throw UnimplementedError();

  /// Files an existing product under one more tag.
  Future<Product> tagProduct(String sku, Tag tag) async =>
      throw UnimplementedError();

  /// Removes a product from the catalogue.
  @Deprecated('Set availability to outOfStock instead.')
  Future<bool> deleteProduct(String sku) async => false;
}
