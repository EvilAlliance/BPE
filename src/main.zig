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

    try bypePairEncodingHashMap(alloc, file);
}

fn bypePairEncodingHashMap(alloc: Allocator, file: std.fs.File) !void {
    const Bpe = BPE(u16);

    var bpe = try Bpe.init(alloc, file);
    try bpe.populate(alloc);
    try bpe.print();
}

pub fn BPE(T: type) type {
    const typeInfo = @typeInfo(T);
    switch (typeInfo) {
        .int => |i| {
            if (i.signedness == .signed) @compileError("Expected unsinged");
            if (i.bits <= 8) @compileError("Cannot Extend the domain if it es less than u8");
        },
        else => @compileError("Invalid Type, Expects any type of unsigned int"),
    }

    return struct {
        const Self = @This();

        const Pair = struct {
            l: T,
            r: T,

            pub const Context = struct {
                pub fn hash(_: @This(), p: Pair) usize {
                    var x: usize = @as(usize, @intCast(p.l)) | (@as(usize, @intCast(p.r)) << 16) | (@as(usize, @intCast(p.l)) << 32) | (@as(usize, @intCast(p.r)) << 48);
                    x ^= x >> 33;
                    x *%= 0xff51afd7ed558ccd;
                    x ^= x >> 33;
                    x *%= 0xc4ceb9fe1a85ec53;
                    x ^= x >> 33;
                    return x;
                }

                pub fn eql(_: @This(), a: Pair, b: Pair) bool {
                    return a.l == b.l and a.r == b.r;
                }
            };

            pub fn init(l: T, r: T) Pair {
                return .{ .l = l, .r = r };
            }
        };

        d: std.HashMapUnmanaged(Pair, u32, Pair.Context, 80) = .{},
        file: std.fs.File,

        pub fn init(alloc: Allocator, file: std.fs.File) Allocator.Error!Self {
            std.log.info("Intializing the BPE", .{});
            var self = Self{ .file = file };
            try self.d.ensureTotalCapacity(alloc, math.pow(u32, math.maxInt(u8), 2));

            return self;
        }

        pub fn populate(self: *Self, alloc: Allocator) !void {
            std.log.info("Populating the Dic", .{});
            var buffer: [math.pow(usize, 2, 10)]u8 = undefined;
            var readerIO = self.file.reader(&buffer);
            const reader = &readerIO.interface;

            var before: T = try reader.takeByte();
            while (reader.takeByte() catch null) |r| {
                const toInsert = Pair.init(before, r);
                defer before = toInsert.r;

                if (self.d.getPtr(toInsert)) |value|
                    value.* += 1
                else
                    try self.d.put(alloc, toInsert, 1);
            }

            std.log.info("Resulting dic with {} unique pairs from {} pairs", .{ self.d.count(), (try self.file.getEndPos()) - 1 });
        }

        pub fn print(self: *const Self) !void {
            std.log.info("Printing Dictionay", .{});
            var buffer: [math.pow(usize, 2, 10)]u8 = undefined;
            const stderr = std.fs.File.stdout();
            var writerIO = stderr.writer(&buffer);

            const w = &writerIO.interface;
            defer w.flush() catch @panic("Failed to print dic state\n");

            _ = try w.write("Resulting Dic:\n");
            for (0..255) |l|
                for (0..255) |r|
                    if (self.d.get(Pair.init(@intCast(l), @intCast(r)))) |x| {
                        try w.print("\t({}, {}) => {}\n", .{ l, r, x });
                    };
        }
    };
}

const std = @import("std");

const Allocator = std.mem.Allocator;
const Order = std.math.Order;
const File = std.fs.File;
const Timer = std.time.Timer;
const io = std.io;
const math = std.math;
const assert = std.debug.assert;
