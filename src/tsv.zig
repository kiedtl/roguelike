const builtin = @import("builtin");
const std = @import("std");
const mem = std.mem;
const meta = std.meta;
const testing = std.testing;
const assert = std.debug.assert;

// pub fn Schema(comptime T: type) type {
//     return struct {
//         field_name: []const u8 = "",
//         parse_to
//     };
// }
pub const TSVSchemaItem = struct {
    field_name: []const u8 = "",
    parse_to: type = usize,
    parse_fn: @TypeOf(_dummy_parse),
    is_array: ?usize = null,
    optional: bool = false,

    fn _dummy_parse(comptime T: type, _: *T, _: []const u8, _: mem.Allocator) bool {
        return false;
    }
};

// TODO: move to separate file (utils.zig?)
pub fn Result(comptime T: type, comptime E: type) type {
    return union(enum) {
        Ok: T,
        Err: E,

        const Self = @This();

        pub fn is_ok(self: Self) bool {
            return switch (self) {
                .Ok => true,
                .Err => false,
            };
        }

        pub fn unwrap(self: Self) T {
            return switch (self) {
                .Ok => |o| o,
                .Err => @panic("Attempted to unwrap error"),
            };
        }
    };
}

pub const TSVParseError = struct {
    type: ErrorType,
    context: Context,

    pub const Context = struct {
        lineno: usize,
        field: usize,
    };

    pub const ErrorType = enum {
        MissingField,
        ErrorParsingField,
        OutOfMemory,
    };
};

pub fn parseCharacter(comptime T: type, result: *T, input: []const u8, _: mem.Allocator) bool {
    switch (@typeInfo(T)) {
        .int => {},
        else => @compileError("Expected int for parsing result type, found '" ++ @typeName(T) ++ "'"),
    }

    if (input[0] != '\'') {
        return false; // ERROR: Invalid character literal
    }

    var found_char = false;
    var utf8 = (std.unicode.Utf8View.init(input) catch {
        return false; // ERROR: Invalid unicode dumbass
    }).iterator();
    _ = utf8.nextCodepointSlice(); // skip beginning quote

    while (utf8.nextCodepointSlice()) |encoded_codepoint| {
        const codepoint = std.unicode.utf8Decode(encoded_codepoint) catch {
            return false; // ERROR: Invalid unicode dumbass
        };
        switch (codepoint) {
            '\'' => {
                if (!found_char) {
                    return false; // ERROR: empty literal
                }

                if (utf8.nextCodepointSlice()) |_| {
                    return false; // ERROR: trailing characters
                }

                return true;
            },
            '\\' => {
                if (found_char) {
                    return false; // ERROR: too many characters
                }

                const encoded_next = utf8.nextCodepointSlice() orelse {
                    return false; // ERROR: incomplete escape sequence
                };
                const next = std.unicode.utf8Decode(encoded_next) catch {
                    return false; // ERROR: Invalid unicode dumbass
                };

                // TODO: \xXX, \uXXXX, \UXXXXXXXX
                const esc: u8 = switch (next) {
                    '\'' => '\'',
                    '\\' => '\\',
                    'n' => '\n',
                    'r' => '\r',
                    'a' => '\x07',
                    '0' => '\x00',
                    't' => '\t',
                    else => return false, // ERROR: invalid escape sequence
                };

                result.* = esc;
                found_char = true;
            },
            else => {
                if (found_char) {
                    return false; // ERROR: too many characters
                }

                result.* = codepoint;
                found_char = true;
            },
        }
    }

    return false; // ERROR: unterminated literal
}

pub fn parseOptionalUtf8String(comptime T: type, result: *T, input: []const u8, alloc: mem.Allocator) bool {
    if (T != ?[]u8) {
        @compileError("Expected ?[]u8, found '" ++ @typeName(T) ++ "'");
    }

    if (mem.eql(u8, input, "nil")) {
        result.* = null;
        return true;
    } else {
        var result_buf: []u8 = undefined;
        const r = parseUtf8String([]u8, &result_buf, input, alloc);
        result.* = result_buf;
        return r;
    }
}

pub fn parseUtf8String(comptime T: type, result: *T, input: []const u8, alloc: mem.Allocator) bool {
    if (T != []u8) {
        @compileError("Expected []u8, found '" ++ @typeName(T) ++ "'");
    }

    if (input[0] != '"') {
        return false; // ERROR: Invalid string
    }

    var tmpbuf = alloc.alloc(u8, input.len) catch return false; // ERROR: OOM
    var buf_i: usize = 0;
    var i: usize = 1; // skip beginning quote

    while (i < input.len) : (i += 1) {
        switch (input[i]) {
            '"' => {
                if (i != (input.len - 1)) {
                    return false; // ERROR: trailing characters
                }

                result.* = alloc.alloc(u8, buf_i) catch return false; // ERROR: OOM
                std.mem.copyForwards(u8, result.*, tmpbuf[0..buf_i]);
                alloc.free(tmpbuf);

                return true;
            },
            '\\' => {
                i += 1;
                if (i == input.len) {
                    return false; // ERROR: incomplete escape sequence
                }

                // TODO: \xXX, \uXXXX, \UXXXXXXXX
                const esc: u8 = switch (input[i]) {
                    '"' => '"',
                    '\\' => '\\',
                    'n' => '\n',
                    'r' => '\r',
                    'a' => '\x07',
                    '0' => '\x00',
                    't' => '\t',
                    else => return false, // ERROR: invalid escape sequence
                };

                tmpbuf[buf_i] = esc;
                buf_i += 1;
            },
            else => {
                tmpbuf[buf_i] = input[i];
                buf_i += 1;
            },
        }
    }

    return false; // ERROR: unterminated string
}

pub fn parsePrimitive(comptime T: type, result: *T, input: []const u8, alloc: mem.Allocator) bool {
    switch (@typeInfo(T)) {
        .int => {
            var inp_start: usize = 0;
            var base: u8 = 0;

            if (input.len >= 3) {
                if (mem.eql(u8, input[0..2], "0x")) {
                    base = 16;
                    inp_start = 2;
                } else if (mem.eql(u8, input[0..2], "0o")) {
                    base = 8;
                    inp_start = 2;
                } else if (mem.eql(u8, input[0..2], "0b")) {
                    base = 2;
                    inp_start = 2;
                } else if (mem.eql(u8, input[0..2], "0s")) { // ???
                    base = 12;
                    inp_start = 2;
                }
            }

            result.* = std.fmt.parseInt(T, input[inp_start..], base) catch return false;
        },
        .float => result.* = std.fmt.parseFloat(T, input) catch return false,
        .bool => {
            if (mem.eql(u8, input, "yea")) {
                result.* = true;
            } else if (mem.eql(u8, input, "nay")) {
                result.* = false;
            } else return false;
        },
        .optional => |optional| {
            if (mem.eql(u8, input, "nil")) {
                result.* = null;
            } else {
                var result_buf: optional.child = undefined;
                const r = parsePrimitive(optional.child, &result_buf, input, alloc);
                result.* = result_buf;
                return r;
            }
        },
        .@"enum" => |enum_info| {
            if (input[0] != '.') return false;

            var found = false;
            inline for (enum_info.fields) |enum_field| {
                if (mem.eql(u8, enum_field.name, input[1..])) {
                    result.* = @enumFromInt(enum_field.value);
                    found = true;
                    //break; // FIXME: Wait for that bug to be fixed, then uncomment
                }
            }

            if (!found) return false;
        },
        .@"union" => |union_info| {
            if (union_info.tag_type) |_| {
                var input_split = mem.splitScalar(u8, input, '=');
                const input_field1 = input_split.next() orelse return false;
                const input_field2 = input_split.next() orelse return false;

                if (input_field1[0] != '.') return false;

                var found = false;
                inline for (union_info.fields) |union_field| {
                    if (mem.eql(u8, union_field.name, input_field1[1..])) {
                        var value: union_field.type = undefined;
                        if (!parsePrimitive(union_field.type, &value, input_field2, alloc))
                            return false;
                        result.* = @unionInit(T, union_field.name, value);
                        found = true;
                        //break; // FIXME: Wait for that bug to be fixed, then uncomment
                    }
                }

                if (!found) return false;
            } else {
                @compileError("Cannot parse untagged union type '" ++ @typeName(T) ++ "'");
            }
        },
        else => @compileError("Cannot parse type '" ++ @typeName(T) ++ "'"),
    }

    return true;
}

pub fn parse(
    comptime T: type,
    comptime schema: []const TSVSchemaItem,
    comptime start_val: T,
    input: []const u8,
    alloc: mem.Allocator,
) Result(std.ArrayList(T), TSVParseError) {
    const S = struct {
        pub fn _err(
            errort: TSVParseError.ErrorType,
            lineno: usize,
            field: usize,
        ) Result(std.ArrayList(T), TSVParseError) {
            return .{
                .Err = .{ .type = errort, .context = .{ .lineno = lineno, .field = field } },
            };
        }
    };

    switch (@typeInfo(T)) {
        .@"struct" => {},
        else => @compileError("Expected struct for parsing result type, found '" ++ @typeName(T) ++ "'"),
    }

    var results = std.ArrayList(T).init(alloc);

    var lines = mem.splitScalar(u8, input, '\n');
    var lineno: usize = 0;

    while (lines.next()) |line| {
        lineno += 1;

        var result: T = start_val;

        // ignore blank/comment lines
        if (line.len == 0 or line[0] == '#') {
            continue;
        }

        var input_fields = mem.splitScalar(u8, line, '\t');

        inline for (schema, 0..) |schema_item, i| {
            if (schema_item.is_array) |array_len| {
                var arr_i: usize = 0;
                while (arr_i < array_len) : (arr_i += 1) {
                    const input_field = mem.trim(u8, input_fields.next() orelse "", " ");

                    if (input_field.len == 0 or input_field[0] == '-') {
                        //@field(result, schema_item.field_name)[arr_i] = schema_item.default_val;
                        continue;
                    }

                    const r = schema_item.parse_fn(
                        schema_item.parse_to,
                        &@field(result, schema_item.field_name)[arr_i],
                        input_field,
                        alloc,
                    );
                    if (!r) {
                        return S._err(.ErrorParsingField, lineno, i);
                    }
                }
            } else {
                const input_field = mem.trim(u8, input_fields.next() orelse "", " ");

                // Handle empty fields
                if (input_field.len == 0 or input_field[0] == '-') {
                    if (schema_item.optional) {
                        //@field(result, schema_item.field_name) = schema_item.default_val;
                    } else {
                        return S._err(.MissingField, lineno, i);
                    }
                } else {
                    const r = schema_item.parse_fn(
                        schema_item.parse_to,
                        &@field(result, schema_item.field_name),
                        input_field,
                        alloc,
                    );
                    if (!r) {
                        return S._err(.ErrorParsingField, lineno, i);
                    }
                }
            }
        }

        results.append(result) catch return S._err(.OutOfMemory, lineno, 0);
    }

    return .{ .Ok = results };
}

// tests {{{
test "integer/float parsing" {
    {
        var buf: usize = 0;
        try testing.expectEqual(true, parsePrimitive(usize, &buf, "3", undefined));
        try testing.expectEqual(@as(usize, 3), buf);

        try testing.expectEqual(true, parsePrimitive(usize, &buf, "0xa", undefined));
        try testing.expectEqual(@as(usize, 10), buf);

        try testing.expectEqual(true, parsePrimitive(usize, &buf, "0o10", undefined));
        try testing.expectEqual(@as(usize, 8), buf);
    }

    {
        var buf: f64 = 0;
        try testing.expectEqual(true, parsePrimitive(f64, &buf, "-3.342e4", undefined));
        try testing.expectEqual(@as(f64, -3.342e4), buf);
    }
}

test "character parsing" {
    var buf: u21 = 'z';

    try testing.expectEqual(true, parseCharacter(u21, &buf, "'a'", undefined));
    try testing.expectEqual(@as(u21, 'a'), buf);

    try testing.expectEqual(true, parseCharacter(u21, &buf, "'\\0'", undefined));
    try testing.expectEqual(@as(u21, '\x00'), buf);

    try testing.expectEqual(true, parseCharacter(u21, &buf, "'\\n'", undefined));
    try testing.expectEqual(@as(u21, '\n'), buf);

    try testing.expectEqual(false, parseCharacter(u21, &buf, "'\\h'", undefined));
    try testing.expectEqual(false, parseCharacter(u21, &buf, "'abc'", undefined));
    try testing.expectEqual(false, parseCharacter(u21, &buf, "'\xc3'", undefined));
}

test "enum parsing" {
    const T = enum { Foo, Bar, Baz };
    var buf: T = undefined;

    try testing.expectEqual(true, parsePrimitive(T, &buf, ".Foo", undefined));
    try testing.expectEqual(@as(T, .Foo), buf);

    try testing.expectEqual(true, parsePrimitive(T, &buf, ".Bar", undefined));
    try testing.expectEqual(@as(T, .Bar), buf);

    try testing.expectEqual(true, parsePrimitive(T, &buf, ".Baz", undefined));
    try testing.expectEqual(@as(T, .Baz), buf);
}

test "union parsing" {
    const T = union(enum) { Foo: usize, Bar: usize, Baz: usize };
    var buf: T = undefined;

    try testing.expectEqual(true, parsePrimitive(T, &buf, ".Foo=3", undefined));
    try testing.expectEqual(@as(T, .{ .Foo = 3 }), buf);

    try testing.expectEqual(true, parsePrimitive(T, &buf, ".Bar=4", undefined));
    try testing.expectEqual(@as(T, .{ .Bar = 4 }), buf);

    try testing.expectEqual(true, parsePrimitive(T, &buf, ".Baz=5", undefined));
    try testing.expectEqual(@as(T, .{ .Baz = 5 }), buf);
}

test "optional integer parsing" {
    var buf: ?usize = 0;

    try testing.expectEqual(true, parsePrimitive(?usize, &buf, "342", undefined));
    try testing.expectEqual(@as(?usize, 342), buf);

    try testing.expectEqual(true, parsePrimitive(?usize, &buf, "nil", undefined));
    try testing.expectEqual(@as(?usize, null), buf);
}

test "string parsing" {
    var membuf: [2048]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(membuf[0..]);

    var buf: []u8 = undefined;

    try testing.expectEqual(true, parseUtf8String([]u8, &buf, "\"\"", fba.allocator()));
    try testing.expectEqualSlices(u8, "", buf);

    try testing.expectEqual(true, parseUtf8String([]u8, &buf, "\"test\"", fba.allocator()));
    try testing.expectEqualSlices(u8, "test", buf);

    try testing.expectEqual(true, parseUtf8String([]u8, &buf, "\"test spaces\"", fba.allocator()));
    try testing.expectEqualSlices(u8, "test spaces", buf);

    try testing.expectEqual(true, parseUtf8String([]u8, &buf, "\"\\n\"", fba.allocator()));
    try testing.expectEqualSlices(u8, "\n", buf);

    try testing.expectEqual(true, parseUtf8String([]u8, &buf, "\"\\\"\"", fba.allocator()));
    try testing.expectEqualSlices(u8, "\"", buf);

    try testing.expectEqual(true, parseUtf8String([]u8, &buf, "\"\\atest\\r\\n\"", fba.allocator()));
    try testing.expectEqualSlices(u8, "\x07test\r\n", buf);
}

test "parsing" {
    var membuf: [2048]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(membuf[0..]);

    const T = struct {
        foo: usize = 2,
        bar: BarT = .Fear,
        baz: f64 = 1.2121,
        bap: []u8 = undefined,

        pub const BarT = enum { Fear, Fire, Fry };
    };

    const schema = [_]TSVSchemaItem{
        .{ .field_name = "bar", .parse_to = T.BarT, .parse_fn = parsePrimitive },
        .{ .field_name = "foo", .parse_to = usize, .parse_fn = parsePrimitive, .optional = true },
        .{ .field_name = "bap", .parse_to = []u8, .parse_fn = parseUtf8String },
        .{ .field_name = "baz", .parse_to = f64, .parse_fn = parsePrimitive },
    };

    {
        const u_result = parse(T, &schema, .{}, ".Fear\t23\t \"simple string here\"\t  19.23 ", fba.allocator());
        try testing.expect(u_result.is_ok());

        const result = u_result.unwrap();
        try testing.expectEqual(@as(usize, 23), result.items[0].foo);
        try testing.expectEqual(@as(T.BarT, .Fear), result.items[0].bar);
        try testing.expectEqual(@as(f64, 19.23), result.items[0].baz);
        try testing.expectEqualSlices(u8, "simple string here", result.items[0].bap);
    }
    {
        const u_result = parse(T, &schema, .{}, ".Fire \t-\t\"test\\\"\\n\\r boop\"\t19.23", fba.allocator());
        try testing.expect(u_result.is_ok());

        const result = u_result.unwrap();
        try testing.expectEqual(@as(usize, 2), result.items[0].foo);
        try testing.expectEqual(@as(T.BarT, .Fire), result.items[0].bar);
        try testing.expectEqual(@as(f64, 19.23), result.items[0].baz);
        try testing.expectEqualSlices(u8, "test\"\n\r boop", result.items[0].bap);
    }
}

test "array parsing" {
    const T = struct {
        name: []u8 = undefined,
        array: [3]usize = [_]usize{ 0, 0, 0 },
    };

    const schema = [_]TSVSchemaItem{
        .{ .field_name = "name", .parse_to = []u8, .parse_fn = parseUtf8String },
        .{ .field_name = "array", .parse_to = usize, .is_array = 3, .parse_fn = parsePrimitive, .optional = true },
    };

    {
        const u_result = parse(T, &schema, .{}, "\"watcher\"\t1\t2\t3", testing.allocator);
        try testing.expect(u_result.is_ok());

        const result = u_result.unwrap();
        defer result.deinit();
        defer testing.allocator.free(result.items[0].name);

        try testing.expectEqualSlices(u8, "watcher", result.items[0].name);
        try testing.expectEqual(@as(usize, 1), result.items[0].array[0]);
        try testing.expectEqual(@as(usize, 2), result.items[0].array[1]);
        try testing.expectEqual(@as(usize, 3), result.items[0].array[2]);
    }

    {
        const u_result = parse(T, &schema, .{}, "\"foobar\"\t - \t83942  \t-", testing.allocator);
        try testing.expect(u_result.is_ok());

        const result = u_result.unwrap();
        defer result.deinit();
        defer testing.allocator.free(result.items[0].name);

        try testing.expectEqualSlices(u8, "foobar", result.items[0].name);
        try testing.expectEqual(@as(usize, 0), result.items[0].array[0]);
        try testing.expectEqual(@as(usize, 83942), result.items[0].array[1]);
        try testing.expectEqual(@as(usize, 0), result.items[0].array[2]);
    }
}
// }}}
