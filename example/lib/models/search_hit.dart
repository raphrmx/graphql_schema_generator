import 'package:acme_catalogue/models/product.dart';
import 'package:acme_catalogue/models/tag.dart';

/// Anything a search can turn up.
// A sealed class is a union the language already writes down: Dart keeps
// every subtype in this library, so the members of the union are known rather
// than guessed.
sealed class SearchHit {
  /// How well the hit matches what was searched for, from 0 to 1.
  final double score;

  const SearchHit(this.score);
}

/// A product the search turned up.
class ProductHit extends SearchHit {
  /// The product itself.
  final Product product;

  const ProductHit(super.score, this.product);
}

/// A tag the search turned up.
class TagHit extends SearchHit {
  /// The tag itself.
  final Tag tag;

  /// How many products carry it.
  final int productCount;

  const TagHit(super.score, this.tag, this.productCount);
}
