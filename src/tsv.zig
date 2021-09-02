const builtin = @import("builtin");
const std = @import("std");
const mem = std.mem;
const meta = std.meta;
const testing = std.testing;
const assert = std.debug.assert;

pub const TSVSchemaItem = struct {
    field_name: []const u8 = "",
    parse_to: type = usize,
    parse_fn: @TypeOf(_dummy_parse),
    optional: bool = false,
    default_val: anytype = undefined, // Only applicable if schema.optional == true

    fn _dummy_parse(comptime T: type, _: *T, __: []const u8, alloc: *mem.Allocator) bool {
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

pub const TSVParseErrorContext = struct {
    lineno: usize,
    field: usize,
};

pub const TSVParseError = union(enum) {
    MissingField: TSVParseErrorContext,
    ErrorParsingField: TSVParseErrorContext,
    OutOfMemory: TSVParseErrorContext,
};

pub fn parseUtf8String(comptime T: type, result: *T, input: []const u8, alloc: *mem.Allocator) bool {
    if (T != []u8) {
        @compileError("Expected []u8, found '" ++ @typeName(T) ++ "'");
    }

    if (input[0] != '"') {
        return false; // ERROR: Invalid string
    }

    var tmpbuf = alloc.alloc(u8, input.len) catch return false; // ERROR: OOM
    var buf_i: usize = 0; // skip beginning quote
    var i: usize = 1; // skip beginning quote

    while (i < input.len) : (i += 1) {
        switch (input[i]) {
            '"' => {
                if (i != (input.len - 1)) {
                    return false; // ERROR: trailing characters
                }

                result.* = alloc.alloc(u8, buf_i) catch return false; // ERROR: OOM
                mem.copy(u8, result.*, tmpbuf[0..buf_i]);
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

pub fn parsePrimitive(comptime T: type, result: *T, input: []const u8, alloc: *mem.Allocator) bool {
    switch (@typeInfo(T)) {
        .Int => result.* = std.fmt.parseInt(T, input, 10) catch return false,
        .Float => result.* = std.fmt.parseFloat(T, input) catch return false,
        .Bool => {
            if (mem.eql(u8, input, "yea")) {
                result = true;
            } else if (mem.eql(u8, input, "nay")) {
                result = false;
            } else return false;
        },
        .Optional => |optional| {
            if (mem.eql(u8, input, "nil")) {
                result.* = null;
            } else {
                var result_buf: optional.child = undefined;
                const r = parsePrimitive(optional.child, &result_buf, input, alloc);
                result.* = result_buf;
                return r;
            }
        },
        .Enum => |enum_info| {
            if (input[0] != '.') return false;

            var found = false;
            inline for (enum_info.fields) |enum_field| {
                if (mem.eql(u8, enum_field.name, input[1..])) {
                    result.* = @intToEnum(T, enum_field.value);
                    found = true;
                    //break; // FIXME: Wait for that bug to be fixed, then uncomment
                }
            }

            if (!found) return false;
        },
        .Union => |union_info| {
            if (union_info.tag_type) |_| {
                var input_split = mem.split(input, "=");
                const input_field1 = input_split.next() orelse return false;
                const input_field2 = input_split.next() orelse return false;

                if (input_field1[0] != '.') return false;

                var found = false;
                inline for (union_info.fields) |union_field| {
                    if (mem.eql(u8, union_field.name, input_field1[1..])) {
                        var value: union_field.field_type = undefined;
                        if (!parsePrimitive(union_field.field_type, &value, input_field2, alloc))
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
    alloc: *mem.Allocator,
) Result(std.ArrayList(T), TSVParseError) {
    const S = struct {
        pub fn _err(
            comptime errort: @TagType(TSVParseError),
            lineno: usize,
            field: usize,
        ) Result(std.ArrayList(T), TSVParseError) {
            return .{
                .Err = @unionInit(
                    TSVParseError,
                    @tagName(errort),
                    .{ .lineno = lineno, .field = field },
                ),
            };
        }
    };

    switch (@typeInfo(T)) {
        .Struct => {},
        else => @compileError("Expected struct for parsing result type, found '" ++ @typeName(T) ++ "'"),
    }

    var results = std.ArrayList(T).init(alloc);

    var lines = mem.split(input, "\n");
    var lineno: usize = 0;

    while (lines.next()) |line| {
        var result: T = start_val;

        // ignore blank/comment lines
        if (line.len == 0 or line[0] == '#') {
            lineno += 1;
            continue;
        }

        var input_fields = mem.split(line, "\t");

        inline for (schema) |schema_item, i| {
            const input_field = input_fields.next() orelse "";

            // Handle empty fields
            if (input_field.len == 0) {
                if (schema_item.optional) {
                    @field(result, schema_item.field_name) = schema_item.default_val;
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

        results.append(result) catch return S._err(.OutOfMemory, lineno, 0);
        lineno += 1;
    }

    return .{ .Ok = results };
}
