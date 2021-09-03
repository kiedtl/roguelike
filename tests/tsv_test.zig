const std = @import("std");
const testing = std.testing;
const mem = std.mem;

const m = @import("src").tsv;

test "integer/float parsing" {
    {
        var buf: usize = 0;
        testing.expectEqual(true, m.parsePrimitive(usize, &buf, "3", undefined));
        testing.expectEqual(@as(usize, 3), buf);

        testing.expectEqual(true, m.parsePrimitive(usize, &buf, "0xa", undefined));
        testing.expectEqual(@as(usize, 10), buf);

        testing.expectEqual(true, m.parsePrimitive(usize, &buf, "0o10", undefined));
        testing.expectEqual(@as(usize, 8), buf);
    }

    {
        var buf: f64 = 0;
        testing.expectEqual(true, m.parsePrimitive(f64, &buf, "-3.342e4", undefined));
        testing.expectEqual(@as(f64, -3.342e4), buf);
    }
}

test "character parsing" {
    var buf: u21 = 'z';

    testing.expectEqual(true, m.parseCharacter(u21, &buf, "'a'", undefined));
    testing.expectEqual(@as(u21, 'a'), buf);

    testing.expectEqual(true, m.parseCharacter(u21, &buf, "'\\0'", undefined));
    testing.expectEqual(@as(u21, '\x00'), buf);

    testing.expectEqual(true, m.parseCharacter(u21, &buf, "'\\n'", undefined));
    testing.expectEqual(@as(u21, '\n'), buf);

    testing.expectEqual(false, m.parseCharacter(u21, &buf, "'\\h'", undefined));
    testing.expectEqual(false, m.parseCharacter(u21, &buf, "'abc'", undefined));
    testing.expectEqual(false, m.parseCharacter(u21, &buf, "'\xc3'", undefined));
}

test "enum parsing" {
    const T = enum { Foo, Bar, Baz };
    var buf: T = undefined;

    testing.expectEqual(true, m.parsePrimitive(T, &buf, ".Foo", undefined));
    testing.expectEqual(@as(T, .Foo), buf);

    testing.expectEqual(true, m.parsePrimitive(T, &buf, ".Bar", undefined));
    testing.expectEqual(@as(T, .Bar), buf);

    testing.expectEqual(true, m.parsePrimitive(T, &buf, ".Baz", undefined));
    testing.expectEqual(@as(T, .Baz), buf);
}

test "union parsing" {
    const T = union(enum) { Foo: usize, Bar: usize, Baz: usize };
    var buf: T = undefined;

    testing.expectEqual(true, m.parsePrimitive(T, &buf, ".Foo=3", undefined));
    testing.expectEqual(@as(T, .{ .Foo = 3 }), buf);

    testing.expectEqual(true, m.parsePrimitive(T, &buf, ".Bar=4", undefined));
    testing.expectEqual(@as(T, .{ .Bar = 4 }), buf);

    testing.expectEqual(true, m.parsePrimitive(T, &buf, ".Baz=5", undefined));
    testing.expectEqual(@as(T, .{ .Baz = 5 }), buf);
}

test "optional integer parsing" {
    var buf: ?usize = 0;

    testing.expectEqual(true, m.parsePrimitive(?usize, &buf, "342", undefined));
    testing.expectEqual(@as(?usize, 342), buf);

    testing.expectEqual(true, m.parsePrimitive(?usize, &buf, "nil", undefined));
    testing.expectEqual(@as(?usize, null), buf);
}

test "string parsing" {
    var membuf: [2048]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(membuf[0..]);

    var buf: []u8 = undefined;

    testing.expectEqual(true, m.parseUtf8String([]u8, &buf, "\"\"", &fba.allocator));
    testing.expectEqualSlices(u8, "", buf);

    testing.expectEqual(true, m.parseUtf8String([]u8, &buf, "\"test\"", &fba.allocator));
    testing.expectEqualSlices(u8, "test", buf);

    testing.expectEqual(true, m.parseUtf8String([]u8, &buf, "\"test spaces\"", &fba.allocator));
    testing.expectEqualSlices(u8, "test spaces", buf);

    testing.expectEqual(true, m.parseUtf8String([]u8, &buf, "\"\\n\"", &fba.allocator));
    testing.expectEqualSlices(u8, "\n", buf);

    testing.expectEqual(true, m.parseUtf8String([]u8, &buf, "\"\\\"\"", &fba.allocator));
    testing.expectEqualSlices(u8, "\"", buf);

    testing.expectEqual(true, m.parseUtf8String([]u8, &buf, "\"\\atest\\r\\n\"", &fba.allocator));
    testing.expectEqualSlices(u8, "\x07test\r\n", buf);
}

test "parsing" {
    var membuf: [2048]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(membuf[0..]);

    const T = struct {
        foo: usize = 0,
        bar: BarT = .Fear,
        baz: f64 = 1.2121,
        bap: []u8 = undefined,

        pub const BarT = enum { Fear, Fire, Fry };
    };

    const schema = [_]m.TSVSchemaItem{
        .{ .field_name = "bar", .parse_to = T.BarT, .parse_fn = m.parsePrimitive },
        .{ .field_name = "foo", .parse_to = usize, .parse_fn = m.parsePrimitive, .optional = true, .default_val = 2 },
        .{ .field_name = "bap", .parse_to = []u8, .parse_fn = m.parseUtf8String },
        .{ .field_name = "baz", .parse_to = f64, .parse_fn = m.parsePrimitive },
    };

    {
        const u_result = m.parse(T, &schema, .{}, ".Fear\t23\t \"simple string here\"\t  19.23 ", &fba.allocator);
        testing.expect(u_result.is_ok());

        const result = u_result.unwrap();
        testing.expectEqual(@as(usize, 23), result.items[0].foo);
        testing.expectEqual(@as(T.BarT, .Fear), result.items[0].bar);
        testing.expectEqual(@as(f64, 19.23), result.items[0].baz);
        testing.expectEqualSlices(u8, "simple string here", result.items[0].bap);
    }
    {
        const u_result = m.parse(T, &schema, .{}, ".Fire \t-\t\"test\\\"\\n\\r boop\"\t19.23", &fba.allocator);
        testing.expect(u_result.is_ok());

        const result = u_result.unwrap();
        testing.expectEqual(@as(usize, 2), result.items[0].foo);
        testing.expectEqual(@as(T.BarT, .Fire), result.items[0].bar);
        testing.expectEqual(@as(f64, 19.23), result.items[0].baz);
        testing.expectEqualSlices(u8, "test\"\n\r boop", result.items[0].bap);
    }
}
