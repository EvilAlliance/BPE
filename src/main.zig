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

const Pair = packed struct {
    const Self = @This();
    l: u16,
    r: u16,
    count: u32 = 1,

    pub fn init(l: u16, r: u16) Self {
        return .{ .l = l, .r = r };
    }

    pub fn compare(self: Self, b: Self) Order {
        if (self.l < b.l) return .lt;
        if (self.l > b.l) return .gt;
        if (self.r < b.r) return .lt;
        if (self.r > b.r) return .gt;

        return .eq;
    }
};

fn bypePairEncoding(alloc: Allocator, reader: *io.Reader) !void {
    var dic: SortedArrayList(Pair, Pair.compare) = .{};
    try dic.ensureTotalCapacity(alloc, std.math.pow(usize, std.math.maxInt(u8), 2));

    var i: usize = 0;
    const reportEach = std.math.pow(usize, 10, 7);

    var time = try Timer.start();
    while (reader.takeByte() catch null) |l| : (i += 1) {
        const r = reader.peekByte() catch break;
        const toInsert = Pair{ .l = l, .r = r };

        if (try dic.putOrGet(alloc, toInsert)) |x| {
            x.count += 1;
        } else {
            std.log.debug("{}", .{dic.list.items.len});
        }

        if (i % reportEach == 0) {
            std.log.info("{} Seconds for {} pairs, count: {}", .{ time.read() / std.time.ns_per_s, i, dic.list.items.len });
        }
    }

    const elapsed = time.lap();
    std.log.info("{} Seconds AVG in each {}", .{ (elapsed / (i / reportEach)) / std.time.ns_per_s, reportEach });
    std.log.info("{} Seconds", .{elapsed / std.time.ns_per_s});

    std.log.info("Resulting Dic", .{});
    for (0..255) |l|
        for (0..255) |r|
            if (dic.get(Pair.init(@intCast(l), @intCast(r)))) |x| {
                std.log.info("    ({}, {}) => {}", .{ l, r, x.count });
            };

    std.log.info("Missing pair", .{});
    for (0..255) |l|
        for (0..255) |r|
            if (dic.get(Pair.init(@intCast(l), @intCast(r))) == null) {
                std.log.warn("    ({}, {})", .{ l, r });
            };
}

const SortedArrayList = @import("SortedArrayList.zig").SortedArrayList;

const std = @import("std");

const Allocator = std.mem.Allocator;
const Order = std.math.Order;
const File = std.fs.File;
const Timer = std.time.Timer;
const io = std.io;
const assert = std.debug.assert;
