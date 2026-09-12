import 'package:acme_catalogue/directives.dart';
import 'package:acme_catalogue/models/product.dart';
import 'package:acme_catalogue/models/product_filter.dart';
import 'package:acme_catalogue/models/search_hit.dart';
import 'package:acme_catalogue/models/sku.dart';

/// What the catalogue can be asked.
// Every public method becomes a field of `Query`: the parameters become the
// arguments, the return type becomes the type of the field.
class Queries {
  /// Reads one product, or null when the catalogue does not hold it.
  Future<Product?> product(Sku sku) async => null;

  /// Lists the products matching [filter], newest first.
  Future<List<Product>> products(ProductFilter filter, {int? limit}) async =>
      const [];

  /// Searches the whole catalogue, best match first.
  Future<List<SearchHit>> search(@Length(min: 2, max: 80) String text) async =>
      const [];

  /// The number of products the catalogue holds.
  Future<int> productCount() async => 0;
}
