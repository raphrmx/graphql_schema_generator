import 'package:graphql_schema_generator/src/naming.dart';
import 'package:test/test.dart';

void main() {
  group('graphQLTypeName', () {
    test('leaves a class name alone in output position', () {
      expect(graphQLTypeName('Product', isInput: false), 'Product');
    });

    test('adds the input suffix in input position', () {
      expect(graphQLTypeName('Product', isInput: true), 'ProductInput');
    });

    test('does not add a suffix the name already carries', () {
      expect(graphQLTypeName('ProductInput', isInput: true), 'ProductInput');
    });

    test('drops the first configured prefix', () {
      expect(
        graphQLTypeName('BmcProduct', isInput: false, stripPrefixes: ['Bmc']),
        'Product',
      );
    });

    test('keeps a name that is nothing but the prefix', () {
      expect(
        graphQLTypeName('Bmc', isInput: false, stripPrefixes: ['Bmc']),
        'Bmc',
      );
    });

    test('honours an empty suffix', () {
      expect(
        graphQLTypeName('Product', isInput: true, inputSuffix: ''),
        'Product',
      );
    });
  });

  group('documentationText', () {
    test('strips the markers', () {
      expect(documentationText('/// A product.'), 'A product.');
    });

    test('keeps the paragraphs of a multi-line comment', () {
      expect(documentationText('/// One.\n///\n/// Two.'), 'One.\n\nTwo.');
    });

    test('reads nothing out of an empty comment', () {
      expect(documentationText('///'), isNull);
      expect(documentationText(null), isNull);
    });
  });
}
