import 'package:acme_catalogue/models/product.dart';
import 'package:acme_catalogue/models/sku.dart';

/// What the catalogue reports as it happens.
// A root like any other. The only difference is the return type: a `Stream`
// is unwrapped the same way a `Future` is, so the field carries what the
// stream carries.
class Subscriptions {
  /// Emits the product every time that SKU is stored or replaced.
  Stream<Product> productChanged(Sku sku) => const Stream.empty();

  /// Emits the number of products whenever the catalogue grows or shrinks.
  Stream<int> productCountChanged() => const Stream.empty();
}
