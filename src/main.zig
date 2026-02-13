pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    try juicyMain(alloc);
}

fn juicyMain(alloc: Allocator) !void {
    const pathAbs = try std.fs.realpathAlloc(alloc, "try.mkv");
    defer alloc.free(pathAbs);

    const file = try std.fs.openFileAbsolute(pathAbs, .{});
    defer file.close();

    var buffer: [std.math.pow(usize, 2, 20)]u8 = undefined;

    var readerLiteral = file.reader(&buffer);
    const reader = &readerLiteral.interface;

    try bypePairEncoding(alloc, reader);
}

fn bypePairEncoding(alloc: Allocator, reader: *io.Reader) !void {
    var dic = std.AutoArrayHashMapUnmanaged(struct { u8, u8 }, usize){};
    defer dic.deinit(alloc);

    var i: usize = 0;
    const reportEach = std.math.pow(usize, 10, 7);

    var time = try Timer.start();
    while (reader.takeByte() catch null) |l| : (i += 1) {
        const r = reader.peekByte() catch break;
        if (dic.getPtr(.{ l, r })) |quant| quant.* += 1 else try dic.put(alloc, .{ l, r }, 1);
        if (i % reportEach == 0) {
            std.log.info("{} Seconds for {} pairs", .{ time.read() / std.time.ns_per_s, i });
        }
    }

    const elapsed = time.lap();
    std.log.info("{} Seconds AVG in each {}", .{ (elapsed / (i / reportEach)) / std.time.ns_per_s, reportEach });
    std.log.info("{} Seconds", .{elapsed / std.time.ns_per_s});

    var it = dic.iterator();
    while (it.next()) |entry| {
        std.log.info("({}, {}) => {}", .{ entry.key_ptr.@"0", entry.key_ptr.@"1", entry.value_ptr.* });
    }
    std.log.warn("This pairs don't exist in the table", .{});
    for (0..255) |l|
        for (0..255) |r|
            if (dic.get(.{ @as(u8, @intCast(l)), @as(u8, @intCast(r)) }) == null) std.log.warn("    ({}, {})", .{ l, r });
}

const std = @import("std");

const Allocator = std.mem.Allocator;
const File = std.fs.File;
const Timer = std.time.Timer;
const io = std.io;
