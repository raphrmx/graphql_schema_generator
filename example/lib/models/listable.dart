/// Anything the catalogue can show on a page.
// An abstract class is an interface, and every class naming it after
// `implements` carries `implements` in the schema.
abstract class Listable {
  /// The name shown to a customer.
  String get label;
}
