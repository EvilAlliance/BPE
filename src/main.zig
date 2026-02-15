pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    const allocGpa = gpa.allocator();
    defer _ = gpa.deinit();

    var arena = std.heap.ArenaAllocator.init(allocGpa);
    const alloc = arena.allocator();
    defer arena.deinit();

    try juicyMain(alloc);
}

fn juicyMain(alloc: Allocator) !void {
    const pathAbs = try std.fs.realpathAlloc(alloc, "enwik9.bin");
    defer alloc.free(pathAbs);

    const file = try std.fs.openFileAbsolute(pathAbs, .{});
    defer file.close();

    var buffer: [std.math.pow(usize, 2, 10)]u8 = undefined;

    var readerLiteral = file.reader(&buffer);
    const reader = &readerLiteral.interface;

    try bypePairEncoding(alloc, reader);
}

fn Pair(comptime individualPair: type) type {
    return struct {
        const Self = @This();

        const Value = struct {
            quantity: usize = 1,
        };
        node: AVL.Node = .{},

        r: individualPair,
        l: individualPair,

        val: Value = .{},

        fn init(l: individualPair, r: individualPair) Self {
            return .{ .l = l, .r = r, .node = .{}, .val = .{} };
        }

        fn compare(self: *const Self, b: *const Self) std.math.Order {
            if (self.l < b.l) return .lt;
            if (self.l > b.l) return .gt;
            if (self.r < b.r) return .lt;
            if (self.r > b.r) return .gt;

            return .eq;
        }

        fn compareNode(selfNode: *const AVL.Node, bNode: *const AVL.Node) std.math.Order {
            const self: *const Self = @fieldParentPtr("node", selfNode);
            const b: *const Self = @fieldParentPtr("node", bNode);

            return self.compare(b);
        }

        pub fn get(a: Allocator, node: *const AVL.Node) []const u8 {
            const self: *const Self = @fieldParentPtr("node", node);
            return std.fmt.allocPrint(a, "({}, {}) v:{}", .{ self.l, self.r, self.val.quantity }) catch unreachable;
        }
    };
}

fn bypePairEncoding(alloc: Allocator, reader: *io.Reader) !void {
    const P = Pair(u16);
    var dic = AVL.AVL(&P.compareNode){};

    var i: usize = 0;
    const reportEach = std.math.pow(usize, 10, 7);

    var toInsert = try alloc.create(P);
    toInsert.* = .{ .l = undefined, .r = undefined };

    var time = try Timer.start();
    while (reader.takeByte() catch null) |l| : (i += 1) {
        const r = reader.peekByte() catch break;
        toInsert.l = l;
        toInsert.r = r;

        if (dic.putOrGet(&toInsert.node)) |x| {
            @as(*P, @fieldParentPtr("node", x)).val.quantity += 1;
        } else {
            toInsert = try alloc.create(P);
            toInsert.* = .{ .l = undefined, .r = undefined };
        }

        if (i % reportEach == 0) {
            std.log.info("{} Seconds for {} pairs, count: {}", .{ time.read() / std.time.ns_per_s, i, dic.count });
        }
    }

    const elapsed = time.lap();
    std.log.info("{} Seconds AVG in each {}", .{ (elapsed / (i / reportEach)) / std.time.ns_per_s, reportEach });
    std.log.info("{} Seconds", .{elapsed / std.time.ns_per_s});

    std.log.warn("This pairs don't exist in the table", .{});
    for (0..255) |l|
        for (0..255) |r|
            if (dic.get(&P.init(@intCast(l), @intCast(r)).node)) |x| {
                const pair: *P = @fieldParentPtr("node", x);
                std.log.warn("    ({}, {}) => {}", .{ l, r, pair.val.quantity });
            };
}

const AVL = @import("AVL.zig");

const std = @import("std");

const Allocator = std.mem.Allocator;
const File = std.fs.File;
const Timer = std.time.Timer;
const io = std.io;
const assert = std.debug.assert;
