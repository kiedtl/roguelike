// Have a good evening, and thank you for choosing the Curly Bracket Format

const std = @import("std");
const meta = std.meta;
const mem = std.mem;
const math = std.math;
const assert = std.debug.assert;
const testing = std.testing;

const LinkedList = @import("list.zig").LinkedList;
const StackBuffer = @import("buffer.zig").StackBuffer;

const KVList = LinkedList(KV);
const StringBuffer = StackBuffer(u8, 2048);

const Value = union(enum) {
    True,
    False,
    None,
    String: StringBuffer,
    List: KVList,
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
    var iter = list.iterator();
    while (iter.nextPtr()) |node| {
        switch (node.key) {
            .Numeric => |n| last = n,
            else => {},
        }
    }
    return last;
}

test "_lastNumericKey()" {
    var gpa = GPA{};
    defer testing.expect(!gpa.deinit());

    var list = KVList.init(&gpa.allocator);
    defer list.deinit();

    testing.expectEqual(_lastNumericKey(&list), null);

    try list.append(KV{ .key = Key{ .String = "hai" }, .value = .None });
    testing.expectEqual(_lastNumericKey(&list), null);

    try list.append(KV{ .key = Key{ .Numeric = 0 }, .value = .None });
    testing.expectEqual(_lastNumericKey(&list), 0);

    try list.append(KV{ .key = Key{ .String = "abcd" }, .value = .None });
    testing.expectEqual(_lastNumericKey(&list), 0);

    try list.append(KV{ .key = Key{ .String = "foobarbaz" }, .value = .None });
    testing.expectEqual(_lastNumericKey(&list), 0);

    try list.append(KV{ .key = Key{ .Numeric = 3 }, .value = .None });
    testing.expectEqual(_lastNumericKey(&list), 3);

    try list.append(KV{ .key = Key{ .String = "bazbarfoo" }, .value = .None });
    testing.expectEqual(_lastNumericKey(&list), 3);

    try list.append(KV{ .key = Key{ .Numeric = 6 }, .value = .None });
    testing.expectEqual(_lastNumericKey(&list), 6);

    try list.append(KV{ .key = Key{ .Numeric = 7 }, .value = .None });
    testing.expectEqual(_lastNumericKey(&list), 7);
}

const Parser = struct {
    input: []const u8,
    index: usize = 0,
    stack: usize = 0,

    const Self = @This();

    const StringParserError = error{
        UnterminatedString,
        StringTooLong,
        InvalidEscape,
    };

    const ParserError = error{
        NoMatchingParen,
        UnknownToken,
        OutOfMemory,
        UnexpectedClosingParen,
        InvalidKeyChar,
        NoMatchingBrace,
        UnexpectedKey,
    } || StringParserError;

    pub fn deinit(data: *KVList) void {
        var iter = data.iterator();
        while (iter.nextPtr()) |node| switch (node.value) {
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
                'a'...'z', '0'...'9', 'A'...'Z' => {},
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
        } else {
            return Value{ .String = StringBuffer.init(word) };
        }
    }

    fn parseString(self: *Self) StringParserError!Value {
        assert(self.input[self.index] == '"');
        self.index += 1;

        var buf = StringBuffer.init("");

        while (self.index < self.input.len) : (self.index += 1) {
            switch (self.input[self.index]) {
                '"' => return Value{ .String = buf },
                '\\' => {
                    self.index += 1;
                    const esc: u8 = switch (self.input[self.index]) {
                        '"' => '"',
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

    pub fn parse(self: *Self, alloc: *mem.Allocator) ParserError!KVList {
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
                '"' => try self.parseString(),
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

                list.append(KV{ .key = key, .value = value }) catch |_| {
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
    defer testing.expect(!gpa.deinit());

    const input = "yea nah nil";
    const output = [_]Value{ .True, .False, .None };
    var p = Parser{ .input = input };

    var res = try p.parse(&gpa.allocator);
    defer Parser.deinit(&res);

    var i: usize = 0;
    var resiter = res.iterator();
    while (resiter.next()) |kv| : (i += 1) {
        const key = Key{ .Numeric = i };
        testing.expectEqual(KV{ .key = key, .value = output[i] }, kv);
    }
}

test "parse strings" {
    var gpa = GPA{};
    defer testing.expect(!gpa.deinit());

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
        var res = try p.parse(&gpa.allocator);
        defer Parser.deinit(&res);

        testing.expectEqual(meta.activeTag(res.nth(0).?.value), .String);
        testing.expectEqualSlices(
            u8,
            res.nth(0).?.value.String.slice(),
            case.output,
        );
    }
}

test "parse basic list" {
    var gpa = GPA{};
    defer testing.expect(!gpa.deinit());

    const input = "yea (nah nil) nah";
    var p = Parser{ .input = input };

    var res = try p.parse(&gpa.allocator);
    defer Parser.deinit(&res);

    testing.expectEqual(res.nth(0).?.value, .True);
    testing.expectEqual(meta.activeTag(res.nth(1).?.value), .List);
    testing.expectEqual(res.nth(1).?.value.List.nth(0).?.value, .False);
    testing.expectEqual(res.nth(1).?.value.List.nth(1).?.value, .None);
    testing.expectEqual(res.nth(2).?.value, .False);
}

test "parse nested list" {
    var gpa = GPA{};
    defer testing.expect(!gpa.deinit());

    const input = "yea ( nah (nah nil) (nah yea  )) nah";
    var p = Parser{ .input = input };

    var res = try p.parse(&gpa.allocator);
    defer Parser.deinit(&res);

    testing.expectEqual(res.nth(0).?.value, .True);
    testing.expectEqual(meta.activeTag(res.nth(1).?.value), .List);
    testing.expectEqual(res.nth(2).?.value, .False);

    var list1 = res.nth(1).?.value.List;

    testing.expectEqual(list1.nth(0).?.value, .False);
    testing.expectEqual(meta.activeTag(list1.nth(1).?.value), .List);
    testing.expectEqual(meta.activeTag(list1.nth(2).?.value), .List);

    testing.expectEqual(list1.nth(1).?.value.List.nth(0).?.value, .False);
    testing.expectEqual(list1.nth(1).?.value.List.nth(1).?.value, .None);

    testing.expectEqual(list1.nth(2).?.value.List.nth(0).?.value, .False);
    testing.expectEqual(list1.nth(2).?.value.List.nth(1).?.value, .True);
}

test "parse values with tags" {
    var gpa = GPA{};
    defer testing.expect(!gpa.deinit());

    const input = "nil [frobnicate]yea [confuzzlementate]nah [fillibigimentate]nil";

    var p = Parser{ .input = input };
    var res = try p.parse(&gpa.allocator);
    defer Parser.deinit(&res);

    // Keys
    testing.expectEqual(res.nth(0).?.key.Numeric, 0);
    testing.expectEqualSlices(u8, res.nth(1).?.key.String, "frobnicate");
    testing.expectEqualSlices(u8, res.nth(2).?.key.String, "confuzzlementate");
    testing.expectEqualSlices(u8, res.nth(3).?.key.String, "fillibigimentate");

    // Values
    testing.expectEqual(res.nth(0).?.value, .None);
    testing.expectEqual(res.nth(1).?.value, .True);
    testing.expectEqual(res.nth(2).?.value, .False);
    testing.expectEqual(res.nth(3).?.value, .None);
}

test "parse lists with tags" {
    var gpa = GPA{};
    defer testing.expect(!gpa.deinit());

    const input = "[xyz](nil [foo]yea [bar]nah [baz]nil nil)";

    var p = Parser{ .input = input };
    var res = try p.parse(&gpa.allocator);
    defer Parser.deinit(&res);

    testing.expectEqualSlices(u8, res.nth(0).?.key.String, "xyz");
    testing.expectEqual(meta.activeTag(res.nth(0).?.value), .List);
    var list = res.nth(0).?.value.List;

    // Keys
    testing.expectEqual(list.nth(0).?.key.Numeric, 0);
    testing.expectEqualSlices(u8, list.nth(1).?.key.String, "foo");
    testing.expectEqualSlices(u8, list.nth(2).?.key.String, "bar");
    testing.expectEqualSlices(u8, list.nth(3).?.key.String, "baz");
    testing.expectEqual(list.nth(4).?.key.Numeric, 1);

    // Values
    testing.expectEqual(list.nth(0).?.value, .None);
    testing.expectEqual(list.nth(1).?.value, .True);
    testing.expectEqual(list.nth(2).?.value, .False);
    testing.expectEqual(list.nth(3).?.value, .None);
    testing.expectEqual(list.nth(4).?.value, .None);
}
