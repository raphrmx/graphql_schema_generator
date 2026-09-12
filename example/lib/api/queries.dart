import 'package:acme_catalogue/models/product.dart';
import 'package:acme_catalogue/models/product_filter.dart';

/// What the catalogue can be asked.
///
/// Every public method becomes a field of `Query`: the parameters become the
/// arguments, the return type becomes the type of the field. Nothing here
/// mentions GraphQL.
class Queries {
  /// Reads one product, or null when the catalogue does not hold it.
  Future<Product?> product(String sku) async => null;

  /// Lists the products matching [filter], newest first.
  Future<List<Product>> products(ProductFilter filter, {int? limit}) async =>
      const [];

  /// The number of products the catalogue holds.
  Future<int> productCount() async => 0;
}
