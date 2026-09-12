/// Whether a product can be ordered right now.
enum Availability {
  /// On the shelf, ready to ship.
  inStock,

  /// Known to the catalogue, not orderable today.
  outOfStock,

  /// Kept for the orders placed before the catalogue was cleaned up.
  @Deprecated('Split into inStock and outOfStock.')
  unknown,
}
