import 'package:graphql_schema_generator/graphql_schema_generator.dart';
import 'package:test/test.dart';

const _string = SdlNamedType('String');
const _id = SdlField(name: 'id', type: SdlNonNullType(_string));

void main() {
  group('SdlSchema.unimplementedInterfaces', () {
    test('is empty when an object type carries the interface', () {
      const schema = SdlSchema(
        definitions: [
          SdlObject(name: 'Node', isInterface: true, fields: [_id]),
          SdlObject(name: 'Product', interfaces: ['Node'], fields: [_id]),
        ],
      );

      expect(schema.unimplementedInterfaces, isEmpty);
    });

    test('names an interface nothing carries', () {
      const schema = SdlSchema(
        definitions: [
          SdlObject(name: 'Node', isInterface: true, fields: [_id]),
          SdlObject(name: 'Product', fields: [_id]),
        ],
      );

      expect(schema.unimplementedInterfaces, ['Node']);
    });

    test('does not count another interface as an implementation', () {
      const schema = SdlSchema(
        definitions: [
          SdlObject(name: 'Node', isInterface: true, fields: [_id]),
          SdlObject(
            name: 'Listable',
            isInterface: true,
            interfaces: ['Node'],
            fields: [_id],
          ),
        ],
      );

      expect(schema.unimplementedInterfaces, ['Node', 'Listable']);
    });

    test('names every interface left without one', () {
      const schema = SdlSchema(
        definitions: [
          SdlObject(name: 'Node', isInterface: true, fields: [_id]),
          SdlObject(name: 'Timestamped', isInterface: true, fields: [_id]),
          SdlObject(name: 'Product', interfaces: ['Node'], fields: [_id]),
        ],
      );

      expect(schema.unimplementedInterfaces, ['Timestamped']);
    });
  });
}
