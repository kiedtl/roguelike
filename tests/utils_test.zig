const std = @import("std");
const testing = std.testing;
const mem = std.mem;

const u = @import("src").utils;

test "sentinel" {
    testing.expectEqual(@TypeOf(u.sentinel([]const u8)), ?u8);
    testing.expectEqual(@TypeOf(u.sentinel([32:0]u23)), ?u23);
    testing.expectEqual(@TypeOf(u.sentinel([128:3]u23)), ?u23);
    testing.expectEqual(@TypeOf(u.sentinel([28]u64)), ?u64);
    testing.expectEqual(@TypeOf(u.sentinel([18:0.34]f64)), ?f64);
    testing.expectEqual(@TypeOf(u.sentinel(*[32:0]u8)), ?u8);
    testing.expectEqual(@TypeOf(u.sentinel(***[32:0]u8)), ?u8);
    testing.expectEqual(@TypeOf(u.sentinel(***[10]isize)), ?isize);

    testing.expectEqual(u.sentinel([]const u8), null);
    testing.expectEqual(u.sentinel([32:0]u23), 0);
    testing.expectEqual(u.sentinel([128:3]u23), 3);
    testing.expectEqual(u.sentinel([28]u64), null);
    testing.expectEqual(u.sentinel([18:0.34]f64), 0.34);
    testing.expectEqual(u.sentinel(*[32:0]u8), 0);
    testing.expectEqual(u.sentinel(***[32:0]u8), 0);
    testing.expectEqual(u.sentinel(***[10]isize), null);
}

test "copy" {
    var one: [32:0]u8 = undefined;
    var two: [32:0]u8 = undefined;
    var three: [15]u8 = [_]u8{0} ** 15;

    // []const u8 => *[32:0]u8
    u.copyZ(&one, "Hello, world!");
    testing.expect(mem.eql(u8, u.used(&one), "Hello, world!"));

    // []const u8 => *[32:0]u8
    u.copyZ(&two, "This is a test!");
    testing.expect(mem.eql(u8, u.used(&two), "This is a test!"));

    // *[32:0]u8 => *[32:0]u8
    u.copyZ(&one, &two);
    testing.expect(mem.eql(u8, u.used(&one), "This is a test!"));

    // *[32:0]u8 => []u8
    u.copyZ(&three, &one);
    testing.expectEqualSlices(u8, &three, "This is a test!");

    // []u8 => []u8
    u.copyZ(&three, "str is 15 chars");
    testing.expectEqualSlices(u8, &three, "str is 15 chars");
}

test "folding text" {
    {
        const str = "  abcd efgh  ijkl mnop ";
        var folder = u.FoldedTextIterator.init(str, 4);
        testing.expectEqualSlices(u8, folder.next().?, "abcd");
        testing.expectEqualSlices(u8, folder.next().?, "efgh");
        testing.expectEqualSlices(u8, folder.next().?, "ijkl");
        testing.expectEqualSlices(u8, folder.next().?, "mnop");
        testing.expectEqual(folder.next(), null);
    }

    {
        const str = "I had a vision when the night was late: a youth came riding toward the palace-gate.";
        var folder = u.FoldedTextIterator.init(str, 10);
        testing.expectEqualSlices(u8, folder.next().?, "I had a");
        testing.expectEqualSlices(u8, folder.next().?, "vision");
        testing.expectEqualSlices(u8, folder.next().?, "when the");
        testing.expectEqualSlices(u8, folder.next().?, "night was");
        testing.expectEqualSlices(u8, folder.next().?, "late: a");
        testing.expectEqualSlices(u8, folder.next().?, "youth");
        testing.expectEqualSlices(u8, folder.next().?, "came");
        testing.expectEqualSlices(u8, folder.next().?, "riding");
        testing.expectEqualSlices(u8, folder.next().?, "toward");
        testing.expectEqualSlices(u8, folder.next().?, "the");
        testing.expectEqualSlices(u8, folder.next().?, "palace-gat");
        testing.expectEqualSlices(u8, folder.next().?, "e.");
        testing.expectEqual(folder.next(), null);
    }
}
