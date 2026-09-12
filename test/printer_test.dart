import 'package:graphql_schema_generator/graphql_schema_generator.dart';
import 'package:test/test.dart';

const _string = SdlNamedType('String');
const _int = SdlNamedType('Int');

void main() {
  group('printTypeRef', () {
    test('wraps a list and a non-null the way the SDL spells them', () {
      expect(printTypeRef(_string), 'String');
      expect(printTypeRef(const SdlNonNullType(_string)), 'String!');
      expect(printTypeRef(const SdlListType(_string)), '[String]');
      expect(
        printTypeRef(
          const SdlNonNullType(SdlListType(SdlNonNullType(_string))),
        ),
        '[String!]!',
      );
    });
  });

  group('printBlockString', () {
    test('keeps a short single line on one line', () {
      expect(printBlockString('A product.'), '"""A product."""');
    });

    test('opens up a line longer than seventy characters', () {
      final long = 'x' * 71;
      expect(printBlockString(long), '"""\n$long\n"""');
    });

    test('opens up a value that spans lines', () {
      expect(printBlockString('one\ntwo'), '"""\none\ntwo\n"""');
    });

    test('escapes the sequence that would close the block early', () {
      expect(printBlockString('a """ b'), '"""a \\""" b"""');
    });

    test('breaks the line when the escape lands at the very end', () {
      expect(printBlockString('ends with """'), '"""\nends with \\"""\n"""');
    });

    test('breaks the line when the value ends with a quote', () {
      expect(printBlockString('says "hi"'), '"""\nsays "hi"\n"""');
    });
  });

  group('printSchema', () {
    test('prints the roots first, then the types by name', () {
      const schema = SdlSchema(
        queryTypeName: 'Query',
        definitions: [
          SdlObject(
            name: 'Zebra',
            fields: [SdlField(name: 'id', type: _string)],
          ),
          SdlObject(
            name: 'Query',
            fields: [SdlField(name: 'zebra', type: _string)],
          ),
          SdlObject(
            name: 'Apple',
            fields: [SdlField(name: 'id', type: _string)],
          ),
        ],
      );

      final names = RegExp(
        r'^type (\w+)',
        multiLine: true,
      ).allMatches(printSchema(schema)).map((m) => m.group(1)).toList();

      expect(names, ['Query', 'Apple', 'Zebra']);
    });

    test('leaves out the built-in scalars', () {
      const schema = SdlSchema(
        definitions: [
          SdlScalar(name: 'String'),
          SdlScalar(name: 'DateTime'),
        ],
      );

      expect(printSchema(schema), 'scalar DateTime\n');
    });

    test('prints a schema block only when a root is named unusually', () {
      const usual = SdlSchema(queryTypeName: 'Query');
      const unusual = SdlSchema(queryTypeName: 'RootQuery');

      expect(printSchema(usual), isNot(contains('schema {')));
      expect(printSchema(unusual), contains('  query: RootQuery'));
    });

    test('keeps arguments on one line until one is described', () {
      const plain = SdlObject(
        name: 'Query',
        fields: [
          SdlField(
            name: 'product',
            type: _string,
            arguments: [
              SdlArgument(name: 'sku', type: SdlNonNullType(_string)),
              SdlArgument(name: 'limit', type: _int, defaultValue: '10'),
            ],
          ),
        ],
      );

      expect(
        printSchema(const SdlSchema(definitions: [plain])),
        contains('  product(sku: String!, limit: Int = 10): String\n'),
      );

      const described = SdlObject(
        name: 'Query',
        fields: [
          SdlField(
            name: 'product',
            type: _string,
            arguments: [
              SdlArgument(
                name: 'sku',
                type: SdlNonNullType(_string),
                description: 'The one to read.',
              ),
            ],
          ),
        ],
      );

      expect(
        printSchema(const SdlSchema(definitions: [described])),
        contains(
          '  product(\n'
          '    """The one to read."""\n'
          '    sku: String!\n'
          '  ): String\n',
        ),
      );
    });

    test('separates a described field from the one before it', () {
      const type = SdlObject(
        name: 'Product',
        fields: [
          SdlField(name: 'sku', type: _string, description: 'The SKU.'),
          SdlField(name: 'label', type: _string, description: 'The label.'),
        ],
      );

      expect(
        printSchema(const SdlSchema(definitions: [type])),
        'type Product {\n'
        '  """The SKU."""\n'
        '  sku: String\n'
        '\n'
        '  """The label."""\n'
        '  label: String\n'
        '}\n',
      );
    });

    test(
      'prints deprecation with its reason, and without when it is the default',
      () {
        const type = SdlObject(
          name: 'Product',
          fields: [
            SdlField(name: 'a', type: _string, deprecationReason: 'Use b.'),
            SdlField(
              name: 'b',
              type: _string,
              deprecationReason: defaultDeprecationReason,
            ),
          ],
        );

        final sdl = printSchema(const SdlSchema(definitions: [type]));

        expect(sdl, contains('  a: String @deprecated(reason: "Use b.")\n'));
        expect(sdl, contains('  b: String @deprecated\n'));
      },
    );

    test('prints a directive definition with its locations', () {
      const directive = SdlDirective(
        name: 'auth',
        locations: ['FIELD_DEFINITION', 'OBJECT'],
        isRepeatable: true,
        arguments: [SdlArgument(name: 'role', type: SdlNonNullType(_string))],
      );

      expect(
        printSchema(const SdlSchema(directives: [directive])),
        'directive @auth(role: String!) repeatable '
        'on FIELD_DEFINITION | OBJECT\n',
      );
    });

    test('prints an interface, its implementations and a union', () {
      const schema = SdlSchema(
        definitions: [
          SdlObject(
            name: 'Node',
            isInterface: true,
            fields: [SdlField(name: 'id', type: SdlNonNullType(_string))],
          ),
          SdlObject(
            name: 'Product',
            interfaces: ['Node'],
            fields: [SdlField(name: 'id', type: SdlNonNullType(_string))],
          ),
          SdlUnion(name: 'Owned', members: ['Product', 'Shop']),
        ],
      );

      final sdl = printSchema(schema);

      expect(sdl, contains('interface Node {'));
      expect(sdl, contains('type Product implements Node {'));
      expect(sdl, contains('union Owned = Product | Shop'));
    });
  });

  group('printSchema, applied directives', () {
    const audited = SdlAppliedDirective(name: 'audited');
    const length = SdlAppliedDirective(
      name: 'length',
      arguments: [
        SdlArgumentValue(name: 'min', value: '1'),
        SdlArgumentValue(name: 'max', value: '120'),
      ],
    );

    test('sits after the name of a type, before its block', () {
      const schema = SdlSchema(
        definitions: [
          SdlObject(
            name: 'Product',
            directives: [audited],
            fields: [SdlField(name: 'id', type: SdlNonNullType(_string))],
          ),
        ],
      );

      expect(printSchema(schema), contains('type Product @audited {'));
    });

    test('sits after what a type implements', () {
      const schema = SdlSchema(
        definitions: [
          SdlObject(
            name: 'Product',
            directives: [audited],
            interfaces: ['Node'],
            fields: [SdlField(name: 'id', type: SdlNonNullType(_string))],
          ),
        ],
      );

      expect(
        printSchema(schema),
        contains('type Product implements Node @audited {'),
      );
    });

    test('follows the type of a field, and the deprecation before it', () {
      const schema = SdlSchema(
        definitions: [
          SdlObject(
            name: 'Product',
            fields: [
              SdlField(
                name: 'label',
                type: SdlNonNullType(_string),
                deprecationReason: 'Gone.',
                directives: [length],
              ),
            ],
          ),
        ],
      );

      expect(
        printSchema(schema),
        contains(
          '  label: String! @deprecated(reason: "Gone.") '
          '@length(min: 1, max: 120)\n',
        ),
      );
    });

    test('follows the default value of an input field', () {
      const schema = SdlSchema(
        definitions: [
          SdlInputObject(
            name: 'ProductDraft',
            fields: [
              SdlField(
                name: 'label',
                type: SdlNonNullType(_string),
                defaultValue: '"none"',
                directives: [length],
              ),
            ],
          ),
        ],
      );

      expect(
        printSchema(schema),
        contains('  label: String! = "none" @length(min: 1, max: 120)\n'),
      );
    });

    test('stays inside the argument list of a field', () {
      const schema = SdlSchema(
        definitions: [
          SdlObject(
            name: 'Query',
            fields: [
              SdlField(
                name: 'search',
                type: SdlNonNullType(_string),
                arguments: [
                  SdlArgument(
                    name: 'text',
                    type: SdlNonNullType(_string),
                    directives: [length],
                  ),
                ],
              ),
            ],
          ),
        ],
      );

      expect(
        printSchema(schema),
        contains('search(text: String! @length(min: 1, max: 120)): String!'),
      );
    });

    test('follows an enum value, a union and a scalar', () {
      const schema = SdlSchema(
        definitions: [
          SdlEnum(
            name: 'Role',
            directives: [audited],
            values: [
              SdlEnumValue(name: 'staff', directives: [audited]),
            ],
          ),
          SdlUnion(name: 'Hit', directives: [audited], members: ['Product']),
          SdlScalar(name: 'Money', directives: [audited]),
        ],
      );

      final sdl = printSchema(schema);

      expect(sdl, contains('enum Role @audited {'));
      expect(sdl, contains('  staff @audited\n'));
      expect(sdl, contains('union Hit @audited = Product'));
      expect(sdl, contains('scalar Money @audited'));
    });

    test('keeps several directives in the order they were read', () {
      const schema = SdlSchema(
        definitions: [
          SdlObject(
            name: 'Product',
            fields: [
              SdlField(
                name: 'label',
                type: SdlNonNullType(_string),
                directives: [audited, length],
              ),
            ],
          ),
        ],
      );

      expect(
        printSchema(schema),
        contains('  label: String! @audited @length(min: 1, max: 120)\n'),
      );
    });
  });
}
