// Have a good evening, and thank you for choosing the Curly Bracket Format

const std = @import("std");
const meta = std.meta;
const mem = std.mem;
const unicode = std.unicode;
const fmt = std.fmt;
const math = std.math;
const assert = std.debug.assert;
const testing = std.testing;

const LinkedList = @import("list.zig").LinkedList;
const StackBuffer = @import("buffer.zig").StackBuffer;

const KVList = std.ArrayList(KV);
const StringBuffer = StackBuffer(u8, 2048);

const Value = union(enum) {
    True,
    False,
    None,
    String: StringBuffer,
    Char: u21,
    List: KVList,
    Usize: usize,
    Isize: isize,
};

const Key = union(enum) {
    Numeric: usize,
    String: []const u8,
};

const KV = struct {
    key: Key,
    value: Value,
};

fn _lastNumericKey(list: *KVList) ?usize {
    var last: ?usize = null;
    for (list.items) |*node| switch (node.key) {
        .Numeric => |n| last = n,
        else => {},
    };
    return last;
}

test "_lastNumericKey()" {
    var gpa = GPA{};

    var list = KVList.init(gpa.allocator());

    try testing.expectEqual(_lastNumericKey(&list), null);

    try list.append(KV{ .key = Key{ .String = "hai" }, .value = .None });
    try testing.expectEqual(_lastNumericKey(&list), null);

    try list.append(KV{ .key = Key{ .Numeric = 0 }, .value = .None });
    try testing.expectEqual(_lastNumericKey(&list), 0);

    try list.append(KV{ .key = Key{ .String = "abcd" }, .value = .None });
    try testing.expectEqual(_lastNumericKey(&list), 0);

    try list.append(KV{ .key = Key{ .String = "foobarbaz" }, .value = .None });
    try testing.expectEqual(_lastNumericKey(&list), 0);

    try list.append(KV{ .key = Key{ .Numeric = 3 }, .value = .None });
    try testing.expectEqual(_lastNumericKey(&list), 3);

    try list.append(KV{ .key = Key{ .String = "bazbarfoo" }, .value = .None });
    try testing.expectEqual(_lastNumericKey(&list), 3);

    try list.append(KV{ .key = Key{ .Numeric = 6 }, .value = .None });
    try testing.expectEqual(_lastNumericKey(&list), 6);

    try list.append(KV{ .key = Key{ .Numeric = 7 }, .value = .None });
    try testing.expectEqual(_lastNumericKey(&list), 7);

    list.deinit();
    try testing.expect(!gpa.deinit());
}

pub const Parser = struct {
    input: []const u8,
    index: usize = 0,
    stack: usize = 0,

    const Self = @This();

    const StringParserError = error{
        UnterminatedString,
        StringTooLong,
        InvalidEscape,
        TooManyCodepointsInChar,
        InvalidUnicode,
    };

    const ParserError = error{
        NoMatchingParen,
        UnknownToken,
        OutOfMemory,
        UnexpectedClosingParen,
        InvalidKeyChar,
        NoMatchingBrace,
        UnexpectedKey,
    } || StringParserError || std.fmt.ParseIntError;

    pub fn deinit(data: *KVList) void {
        for (data.items) |*node| switch (node.value) {
            .List => |*l| deinit(l),
            else => {},
        };
        data.deinit();
    }

    fn parseKey(self: *Self) ParserError![]const u8 {
        assert(self.input[self.index] == '[');
        self.index += 1;

        const oldi = self.index;
        while (self.index < self.input.len) : (self.index += 1) {
            switch (self.input[self.index]) {
                ']' => return self.input[oldi..self.index],
                'a'...'z', '_', '0'...'9', 'A'...'Z' => {},
                else => return error.InvalidKeyChar,
            }
        }

        return error.NoMatchingBrace;
    }

    fn parseValue(self: *Self) ParserError!Value {
        const oldi = self.index;
        while (self.index < self.input.len) : (self.index += 1) {
            switch (self.input[self.index]) {
                0x09, 0x0a...0x0d, 0x20, '(', ')', '[', ']' => break,
                else => {},
            }
        }

        const word = self.input[oldi..self.index];
        assert(word.len > 0);

        // parse() expects index to point to last non-word char, so move index
        // back
        self.index -= 1;

        if (mem.eql(u8, word, "yea")) {
            return .True;
        } else if (mem.eql(u8, word, "nah")) {
            return .False;
        } else if (mem.eql(u8, word, "nil")) {
            return .None;
        } else if (word[0] >= '0' and word[0] <= '9') {
            // TODO: u8, u16, u21, u32, u64, u128, and signed variants.
            //       (add them as needed...)
            // TODO: multibase (0x, 0o, 0b)
            if (mem.endsWith(u8, word, "z")) {
                const num = try std.fmt.parseInt(usize, word[0 .. word.len - 1], 10);
                return Value{ .Usize = num };
            } else if (mem.endsWith(u8, word, "i")) {
                const num = try std.fmt.parseInt(isize, word[0 .. word.len - 1], 10);
                return Value{ .Isize = num };
            } else {
                return Value{ .String = StringBuffer.init(word) };
            }
        } else {
            return Value{ .String = StringBuffer.init(word) };
        }
    }

    fn parseString(self: *Self, mode: u8) StringParserError!Value {
        assert(self.input[self.index] == mode);
        self.index += 1;

        var buf = StringBuffer.init("");

        while (self.index < self.input.len) : (self.index += 1) {
            switch (self.input[self.index]) {
                '\'' => {
                    if ((unicode.utf8CountCodepoints(buf.constSlice()) catch return error.InvalidUnicode) > 1)
                        return error.TooManyCodepointsInChar;
                    return Value{ .Char = unicode.utf8Decode(buf.constSlice()) catch return error.InvalidUnicode };
                },
                '"' => {
                    return Value{ .String = buf };
                },
                '\\' => {
                    self.index += 1;
                    const esc: u8 = switch (self.input[self.index]) {
                        '"' => '"',
                        '\'' => '\'',
                        '\\' => '\\',
                        'n' => '\n',
                        'r' => '\r',
                        'a' => 0x07,
                        '0' => 0x00,
                        't' => '\t',
                        else => return error.InvalidEscape,
                    };
                    buf.append(esc) catch return error.StringTooLong;
                },
                else => buf.append(self.input[self.index]) catch return error.StringTooLong,
            }
        }

        return error.UnterminatedString;
    }

    pub fn parse(self: *Self, alloc: mem.Allocator) ParserError!KVList {
        self.stack += 1;

        if (self.stack > 1) {
            assert(self.input[self.index] == '(');
            self.index += 1;
        }

        var list = KVList.init(alloc);
        var next_key: ?[]const u8 = null;

        while (self.index < self.input.len) : (self.index += 1) {
            const v: ?Value = switch (self.input[self.index]) {
                '(' => Value{ .List = try self.parse(alloc) },
                ')' => {
                    if (self.stack <= 1) {
                        return error.UnexpectedClosingParen;
                    }

                    self.stack -= 1;
                    return list;
                },
                '[' => c: {
                    if (next_key) |_| {
                        return error.UnexpectedKey;
                    }

                    next_key = try self.parseKey();
                    break :c null;
                },
                ']', 0x09, 0x0a...0x0d, 0x20 => continue,
                '"' => try self.parseString('"'),
                '\'' => try self.parseString('\''),
                else => try self.parseValue(),
            };

            if (v) |value| {
                var key: Key = undefined;

                if (next_key) |nk| {
                    key = Key{ .String = nk };
                    next_key = null;
                } else if (_lastNumericKey(&list)) |ln| {
                    key = Key{ .Numeric = ln + 1 };
                } else {
                    key = Key{ .Numeric = 0 };
                }

                list.append(KV{ .key = key, .value = value }) catch {
                    return error.OutOfMemory;
                };
            }
        }

        if (self.stack > 1) {
            // We didn't find a matching paren
            return error.NoMatchingParen;
        } else {
            return list;
        }
    }
};

// Use a GPA for tests as then we get an error when there's a memory leak.
// Also, the StringBuffers are too big for a FBA.
const GPA = std.heap.GeneralPurposeAllocator(.{});

test "parse values" {
    var gpa = GPA{};

    const input = "yea nah nil 'f' 129z 0z";
    const output = [_]Value{ .True, .False, .None, .{ .Char = 'f' }, .{ .Usize = 129 }, .{ .Usize = 0 } };
    var p = Parser{ .input = input };

    var res = try p.parse(gpa.allocator());

    for (res.items, 0..) |kv, i| {
        const key = Key{ .Numeric = i };
        try testing.expectEqual(KV{ .key = key, .value = output[i] }, kv);
    }

    Parser.deinit(&res);
    try testing.expect(!gpa.deinit());
}

test "parse strings" {
    var gpa = GPA{};

    const Case = struct { input: []const u8, output: []const u8 };
    const cases = [_]Case{
        Case{ .input = "\"test\"", .output = "test" },
        Case{ .input = "\"henlo world\"", .output = "henlo world" },
        Case{ .input = "\"hi\n\n\"", .output = "hi\n\n" },
        Case{ .input = "\"abcd\r\nabcd\r\n\\\\\"", .output = "abcd\r\nabcd\r\n\\" },
        Case{ .input = "\"\\\" \\\" \\\" \\\\ \"", .output = "\" \" \" \\ " },
    };

    for (&cases) |case| {
        var p = Parser{ .input = case.input };
        var res = try p.parse(gpa.allocator());

        try testing.expectEqual(meta.activeTag(res.items[0].value), .String);
        try testing.expectEqualSlices(
            u8,
            res.items[0].value.String.slice(),
            case.output,
        );

        Parser.deinit(&res);
    }

    try testing.expect(!gpa.deinit());
}

test "parse basic list" {
    var gpa = GPA{};

    const input = "yea (nah nil) nah";
    var p = Parser{ .input = input };

    var res = try p.parse(gpa.allocator());

    try testing.expectEqual(res.items[0].value, .True);
    try testing.expectEqual(meta.activeTag(res.items[1].value), .List);
    try testing.expectEqual(res.items[1].value.List.items[0].value, .False);
    try testing.expectEqual(res.items[1].value.List.items[1].value, .None);
    try testing.expectEqual(res.items[2].value, .False);

    Parser.deinit(&res);
    try testing.expect(!gpa.deinit());
}

test "parse nested list" {
    var gpa = GPA{};

    const input = "yea ((nah nil) nah (nah yea  )) nah";
    var p = Parser{ .input = input };

    var res = try p.parse(gpa.allocator());

    try testing.expectEqual(res.items[0].value, .True);
    try testing.expectEqual(meta.activeTag(res.items[1].value), .List);

    const list1 = res.items[1].value.List;

    try testing.expectEqual(meta.activeTag(list1.items[0].value), .List);
    try testing.expectEqual(list1.items[1].value, .False);
    try testing.expectEqual(meta.activeTag(list1.items[2].value), .List);

    try testing.expectEqual(list1.items[0].value.List.items[0].value, .False);
    try testing.expectEqual(list1.items[0].value.List.items[1].value, .None);

    try testing.expectEqual(list1.items[2].value.List.items[0].value, .False);
    try testing.expectEqual(list1.items[2].value.List.items[1].value, .True);

    Parser.deinit(&res);
    try testing.expect(!gpa.deinit());
}

test "parse values with tags" {
    var gpa = GPA{};

    const input = "nil [frobnicate]yea [confuzzlementate]nah [fillibigimentate]nil";

    var p = Parser{ .input = input };
    var res = try p.parse(gpa.allocator());

    // Keys
    try testing.expectEqual(res.items[0].key.Numeric, 0);
    try testing.expectEqualSlices(u8, res.items[1].key.String, "frobnicate");
    try testing.expectEqualSlices(u8, res.items[2].key.String, "confuzzlementate");
    try testing.expectEqualSlices(u8, res.items[3].key.String, "fillibigimentate");

    // Values
    try testing.expectEqual(res.items[0].value, .None);
    try testing.expectEqual(res.items[1].value, .True);
    try testing.expectEqual(res.items[2].value, .False);
    try testing.expectEqual(res.items[3].value, .None);

    Parser.deinit(&res);
    try testing.expect(!gpa.deinit());
}

test "parse lists with tags" {
    var gpa = GPA{};

    const input = "[xyz](nil [foo]yea [bar]nah [baz]nil nil)";

    var p = Parser{ .input = input };
    var res = try p.parse(gpa.allocator());

    try testing.expectEqualSlices(u8, res.items[0].key.String, "xyz");
    try testing.expectEqual(meta.activeTag(res.items[0].value), .List);
    const list = res.items[0].value.List;

    // Keys
    try testing.expectEqual(list.items[0].key.Numeric, 0);
    try testing.expectEqualSlices(u8, list.items[1].key.String, "foo");
    try testing.expectEqualSlices(u8, list.items[2].key.String, "bar");
    try testing.expectEqualSlices(u8, list.items[3].key.String, "baz");
    try testing.expectEqual(list.items[4].key.Numeric, 1);

    // Values
    try testing.expectEqual(list.items[0].value, .None);
    try testing.expectEqual(list.items[1].value, .True);
    try testing.expectEqual(list.items[2].value, .False);
    try testing.expectEqual(list.items[3].value, .None);
    try testing.expectEqual(list.items[4].value, .None);

    Parser.deinit(&res);
    try testing.expect(!gpa.deinit());
}

pub fn deserializeValue(comptime T: type, val: Value, default: ?T) !T {
    switch (T) {
        []const u8 => return switch (val) {
            .String => |b| b.constSlice(),
            else => error.E,
        },
        else => {},
    }

    return switch (@typeInfo(T)) {
        .noreturn, .void, .type => error.E,
        .vector, .comptime_int, .comptime_float, .undefined => error.E,
        .bool => switch (val) {
            .True => true,
            .False => false,
            else => error.E,
        },
        .int => switch (val) {
            .Char => |c| @as(T, @intCast(c)),
            .String => |s| fmt.parseInt(T, s.constSlice(), 0) catch error.E,
            .Usize => |u| if (T == usize) u else error.E,
            .Isize => |u| if (T == isize) u else error.E,
            else => error.E,
        },
        .float => switch (val) {
            .String => |s| fmt.parseFloat(T, s.constSlice()) catch error.E,
            else => error.E,
        },
        .@"enum" => switch (val) {
            .String => |s| std.meta.stringToEnum(T, s.constSlice()) orelse error.E,
            else => error.E,
        },
        .@"union" => switch (val) {
            .List => |l| {
                if (l.items.len > 2 or l.items.len == 0) return error.E;
                const tag = try deserializeValue(std.meta.Tag(T), l.items[0].value, null);
                inline for (std.meta.fields(T)) |field| {
                    if (mem.eql(u8, field.name, @tagName(tag))) {
                        if (field.type == void) {
                            if (l.items.len == 2) return error.E;
                            return @unionInit(T, field.name, {});
                        } else {
                            if (l.items.len == 1) return error.E;
                            const fld = try deserializeValue(field.type, l.items[1].value, null);
                            return @unionInit(T, field.name, fld);
                        }
                    }
                }
                return error.E;
            },
            else => error.E,
        },
        .optional => |optional| switch (val) {
            .None => null,
            else => try deserializeValue(optional.child, val, null),
        },
        .@"struct" => switch (val) {
            .List => |l| try deserializeStruct(T, l, default.?),
            else => error.E,
        },
        else => @compileError(@tagName(@typeInfo(T)) ++ " isn't implemented."),
    };
}

pub fn deserializeStruct(comptime T: type, data: KVList, initial: T) !T {
    const struct_info = @typeInfo(T).@"struct";
    const fields = struct_info.fields;

    var output: T = initial;

    for (data.items) |node| {
        // Using block labels and 'break :block;' instead of the clunky 'found'
        // variables segfaults Zig (See: #2727)
        //
        // https://github.com/ziglang/zig/issues/2727
        switch (node.key) {
            .Numeric => |n| {
                var found: bool = false;
                inline for (fields, 0..) |f, i| {
                    if (n == i) {
                        @field(output, f.name) = try deserializeValue(f.type, node.value, f.defaultValue());
                        found = true;
                    }
                }
                if (!found) return error.TooManyItems;
            },
            .String => |s| {
                var found: bool = false;
                inline for (fields) |f| {
                    if (mem.eql(u8, s, f.name)) {
                        @field(output, f.name) = try deserializeValue(f.type, node.value, f.defaultValue());
                        found = true;
                    }
                }
                if (!found) return error.NoSuchTag;
            },
        }
    }

    return output;
}

test "value deserial" {
    try testing.expectEqual(deserializeValue(bool, .True, null), true);
    try testing.expectEqual(deserializeValue(bool, .False, null), false);

    try testing.expectEqual(deserializeValue(usize, Value{ .String = StringBuffer.init("0") }, null), 0);
    try testing.expectEqual(deserializeValue(usize, Value{ .String = StringBuffer.init("231") }, null), 231);

    try testing.expectEqual(deserializeValue(isize, Value{ .String = StringBuffer.init("-1") }, null), -1);
    try testing.expectEqual(deserializeValue(isize, Value{ .String = StringBuffer.init("91") }, null), 91);

    try testing.expectEqual(deserializeValue(f64, Value{ .String = StringBuffer.init("15.21") }, null), 15.21);
}

test "struct deserial" {
    const Type = struct { foo: usize = 0, bar: bool = true, baz: isize = 0 };

    var gpa = GPA{};

    const input = "([foo]12 [bar]yea [baz]-2)";

    var p = Parser{ .input = input };
    var res = try p.parse(gpa.allocator());

    const r = try deserializeStruct(Type, res.items[0].value.List, .{});
    try testing.expectEqual(r.foo, 12);
    try testing.expectEqual(r.bar, true);
    try testing.expectEqual(r.baz, -2);

    Parser.deinit(&res);
    try testing.expect(!gpa.deinit());
}

test "union deserial" {
    const Type = union(enum) { foo: usize, bar: bool, baz: isize, flu };

    var gpa = GPA{};

    {
        const input = "(foo 12)";
        var p = Parser{ .input = input };
        var res = try p.parse(gpa.allocator());
        defer Parser.deinit(&res);
        try testing.expectEqual(deserializeValue(Type, res.items[0].value, null), .{ .foo = 12 });
    }
    {
        const input = "(bar nah)";
        var p = Parser{ .input = input };
        var res = try p.parse(gpa.allocator());
        defer Parser.deinit(&res);
        try testing.expectEqual(deserializeValue(Type, res.items[0].value, null), .{ .bar = false });
    }
    {
        const input = "(baz -49)";
        var p = Parser{ .input = input };
        var res = try p.parse(gpa.allocator());
        defer Parser.deinit(&res);
        try testing.expectEqual(deserializeValue(Type, res.items[0].value, null), .{ .baz = -49 });
    }
    {
        const input = "(flu)";
        var p = Parser{ .input = input };
        var res = try p.parse(gpa.allocator());
        defer Parser.deinit(&res);
        try testing.expectEqual(deserializeValue(Type, res.items[0].value, null), .flu);
    }

    try testing.expect(!gpa.deinit());
}
