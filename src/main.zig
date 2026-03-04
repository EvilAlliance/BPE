pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    const allocGpa = gpa.allocator();
    defer _ = gpa.deinit();

    try juicyMain(allocGpa);
}

fn juicyMain(alloc: Allocator) !void {
    const pathAbs = try std.fs.realpathAlloc(alloc, "./wikipediaExample.txt");
    defer alloc.free(pathAbs);

    const file = try std.fs.openFileAbsolute(pathAbs, .{});
    defer file.close();

    try bypePairEncodingHashMap(alloc, file);
}

fn bypePairEncodingHashMap(alloc: Allocator, file: std.fs.File) !void {
    const Bpe = BPE(u16);
    var arena = std.heap.ArenaAllocator.init(alloc);
    const arenaAlloc = arena.allocator();

    var bpe = try Bpe.init(alloc, file);
    try bpe.populate(alloc);
    while (bpe.searchMaxPair()) |toSwap| {
        const newItem = bpe.reserveItem();
        try bpe.iterate(alloc, toSwap, newItem);
        if (bpe.addPair(arenaAlloc, alloc, toSwap, newItem)) break;

        try bpe.print();
    }
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

        const PairCounting = std.HashMapUnmanaged(Pair, u32, Pair.Context, 50);
        const RevDic = std.HashMapUnmanaged(T, Pair, std.hash_map.AutoContext(T), 50);
        const Dic = Trie(T);

        count: PairCounting = .{},
        dic: *Dic,
        revDic: RevDic = .{},
        file: std.fs.File,
        newItem: T = math.maxInt(u8) + 1,

        pub fn init(alloc: Allocator, file: std.fs.File) Allocator.Error!Self {
            std.log.info("Intializing the BPE", .{});
            var self = Self{ .file = file, .dic = try .init(alloc) };
            try self.count.ensureTotalCapacity(alloc, math.pow(u32, math.maxInt(u8), 2));
            try self.revDic.ensureTotalCapacity(alloc, math.maxInt(u16));

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

                if (self.count.getPtr(toInsert)) |value|
                    value.* += 1
                else
                    try self.count.put(alloc, toInsert, 1);
            }

            std.log.info("Resulting dic with {} unique pairs from {} pairs", .{ self.count.count(), (try self.file.getEndPos()) - 1 });
        }

        pub fn searchMaxPair(self: *Self) ?Pair {
            if (self.count.count() == 0) return null;
            var it = self.count.iterator();

            const first = it.next().?;
            var max: struct { Pair, u32 } = .{ first.key_ptr.*, first.value_ptr.* };

            while (it.next()) |entry| {
                if (max.@"1" < entry.value_ptr.*) max = .{ entry.key_ptr.*, entry.value_ptr.* };
            }

            return if (max.@"1" > 1) max.@"0" else null;
        }

        pub fn reserveItem(self: *Self) T {
            const ret = self.newItem;
            self.newItem += 1;
            return ret;
        }

        pub fn addPair(self: *Self, arenaAllocator: Allocator, alloc: Allocator, pair: Pair, newItem: T) !bool {
            std.log.info("Adding to dic new char for domain {x}", .{self.newItem});

            const current = try insertBasicDomian(arenaAllocator, self.dic, self.revDic, pair);
            current.setVaue(newItem);

            try self.revDic.put(alloc, newItem, pair);

            return self.newItem == math.maxInt(T);
        }

        fn insertBasicDomian(alloc: Allocator, trie: *Dic, revDic: RevDic, pair: Pair) !*Dic {
            var current: *Dic = trie;
            if (pair.l <= math.maxInt(u8)) {
                current = try current.insertChar(alloc, @intCast(pair.l));
            } else {
                current = try insertBasicDomian(alloc, current, revDic, revDic.get(pair.l).?);
            }

            if (pair.r <= math.maxInt(u8)) {
                current = try current.insertChar(alloc, @intCast(pair.r));
            } else {
                current = try insertBasicDomian(alloc, current, revDic, revDic.get(pair.r).?);
            }

            return current;
        }

        pub fn iterate(self: *Self, alloc: Allocator, pairToChange: Pair, newItem: T) !void {
            std.log.info("Logically Replacing ({x}, {x}) with {x}", .{ pairToChange.l, pairToChange.r, newItem });

            const ctx: Pair.Context = .{};

            var buffer: [math.pow(usize, 2, 10)]u8 = undefined;
            var readerIO = self.file.reader(&buffer);
            const reader = &readerIO.interface;

            var before: ?T = null;
            var l: ?T = try getToken(self.dic, reader);
            while (l) |left| {
                const r = try getToken(self.dic, reader) orelse break;
                const current = Pair.init(left, r);

                if (ctx.eql(current, pairToChange)) {
                    if (before) |b| {
                        self.count.getPtr(Pair.init(b, left)).?.* -= 1;

                        const toInsert = Pair.init(b, newItem);
                        if (self.count.getPtr(toInsert)) |value|
                            value.* += 1
                        else
                            try self.count.put(alloc, toInsert, 1);
                    }

                    if (self.count.getPtr(current)) |count| count.* -= 1;

                    const after = try getToken(self.dic, reader);

                    if (after) |a| {
                        self.count.getPtr(Pair.init(r, a)).?.* -= 1;

                        const toInsert = Pair.init(newItem, a);
                        if (self.count.getPtr(toInsert)) |value|
                            value.* += 1
                        else
                            try self.count.put(alloc, toInsert, 1);
                    }

                    before = newItem;
                    l = after;
                } else {
                    before = left;
                    l = r;
                }
            }

            // WARN: Printing the counting the quantity of pairs is a little more dificult
            std.log.info("Resulting dic with {} unique pairs", .{self.count.count()});
        }

        fn getToken(dic: *Dic, r: *io.Reader) !?T {
            const first = r.takeByte() catch |err| switch (err) {
                error.EndOfStream => return null,
                else => return @errorCast(err),
            };

            var right = dic.getChar(first) orelse return first;

            while (r.peekByte() catch return right.getValue() orelse first) |peeked| {
                const next = right.getChar(peeked) orelse break;
                assert(next.getValue() != null);
                _ = r.takeByte();
                right = next;
            }

            return right.getValue() orelse first;
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
                    if (self.count.get(Pair.init(@intCast(l), @intCast(r)))) |x| {
                        try w.print("\t({x}, {x}) => {}\n", .{ l, r, x });
                    };
        }
    };
}

test {
    _ = @import("Trie.zig");
}

const Trie = @import("Trie.zig").Trie;

const std = @import("std");

const Allocator = std.mem.Allocator;
const Order = std.math.Order;
const File = std.fs.File;
const Timer = std.time.Timer;
const io = std.io;
const math = std.math;
const assert = std.debug.assert;
