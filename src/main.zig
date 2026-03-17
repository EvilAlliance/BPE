pub const std_options: std.Options = .{
    .log_level = .debug,
};

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    const allocGpa = gpa.allocator();
    defer _ = gpa.deinit();

    try juicyMain(allocGpa);
}

fn juicyMain(alloc: Allocator) !void {
    var args = try std.process.argsWithAllocator(alloc);
    defer args.deinit();

    const exeName = args.next() orelse "BPE";
    const inputPath = args.next() orelse {
        std.log.err("Usage: {s} <file>", .{exeName});
        return error.InvalidArguments;
    };

    const pathAbs = try std.fs.realpathAlloc(alloc, inputPath);
    defer alloc.free(pathAbs);

    const file = try std.fs.openFileAbsolute(pathAbs, .{});
    defer file.close();

    try bypePairEncodingHashMap(alloc, file);
}

fn bypePairEncodingHashMap(alloc: Allocator, file: std.fs.File) !void {
    const Bpe = BPE(u16);
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const arenaAlloc = arena.allocator();

    var bpe = try Bpe.init(arenaAlloc, file);
    defer bpe.deinit(alloc, arenaAlloc);
    try bpe.populate(alloc);

    if (build_options.trace) {
        try bpe.printCount();
        try bpe.printText();
    }

    while (bpe.searchMaxPair()) |toSwap| {
        const newItem = bpe.reserveItem();
        try bpe.iterate(alloc, toSwap, newItem);
        if (try bpe.addPair(arenaAlloc, alloc, toSwap, newItem)) break;

        if (build_options.trace) {
            try bpe.printDic();
            try bpe.printCount();
            try bpe.printText();
        }

        if (build_options.debug) try bpe.verifyCount(alloc);
    }

    try bpe.printCount();
    try bpe.printText();
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

            pub fn format(self: Pair, w: *io.Writer) !void {
                try w.writeByte('(');
                if (self.l <= math.maxInt(u8))
                    try w.print("{c}", .{@as(u8, @intCast(self.l))})
                else
                    try w.print("{x}", .{self.l});

                _ = try w.write(", ");

                if (self.r <= math.maxInt(u8))
                    try w.print("{c}", .{@as(u8, @intCast(self.r))})
                else
                    try w.print("{x}", .{self.r});

                try w.writeByte(')');
            }
        };

        const BufferLen = std.math.pow(usize, 2, 10);

        const PairCounting = std.HashMapUnmanaged(Pair, u32, Pair.Context, 50);
        const RevDic = std.HashMapUnmanaged(T, Pair, std.hash_map.AutoContext(T), 50);
        const Dic = Trie(struct {
            min: T,
            parent: ?T = null,
            value: ?T = null,

            pub fn format(self: @This(), w: *io.Writer) !void {
                try w.print("{?x}(min: {x}, parent: {?x})", .{ self.value, self.min, self.parent });
            }
        });

        count: PairCounting = .{},
        dic: *Dic,
        revDic: RevDic = .{},
        file: std.fs.File,
        newItem: T = math.maxInt(u8) + 1,

        pub fn init(arenaAlloc: Allocator, file: std.fs.File) Allocator.Error!Self {
            std.log.info("Intializing the BPE", .{});
            const self = Self{ .file = file, .dic = try .init(arenaAlloc) };
            return self;
        }

        pub fn deinit(self: *Self, alloc: Allocator, arenaAlloc: Allocator) void {
            std.log.info("Deintializing the BPE", .{});
            self.revDic.deinit(alloc);
            self.count.deinit(alloc);
            self.dic.deinit(arenaAlloc);
        }

        pub fn populate(self: *Self, alloc: Allocator) !void {
            std.log.info("Populating the Dic", .{});
            var timer: ?std.time.Timer = null;

            if (build_options.bench) {
                timer = try std.time.Timer.start();
            }

            var buffer: [BufferLen]u8 = undefined;
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

            if (build_options.bench) {
                std.log.debug("It took {}s", .{@as(f64, @floatFromInt(timer.?.lap())) / std.time.ns_per_s});
            }

            std.log.info("Resulting dic with {} unique pairs from {} pairs", .{ self.count.count(), (try self.file.getEndPos()) - 1 });
        }

        pub fn searchMaxPair(self: *Self) ?Pair {
            if (self.count.count() == 0) return null;
            var it = self.count.iterator();

            const first = it.next().?;
            var max: struct { Pair, u32 } = .{ first.key_ptr.*, first.value_ptr.* };

            while (it.next()) |entry| {
                if (max.@"1" < entry.value_ptr.*)
                    max = .{ entry.key_ptr.*, entry.value_ptr.* }
                else if (max.@"1" == entry.value_ptr.* and (entry.key_ptr.l < max.@"0".l and entry.key_ptr.r < max.@"0".r))
                    max = .{ entry.key_ptr.*, entry.value_ptr.* };
            }

            return if (max.@"1" > 1) max.@"0" else null;
        }

        pub fn reserveItem(self: *Self) T {
            const ret = self.newItem;
            self.newItem += 1;
            return ret;
        }

        pub fn addPair(self: *Self, arenaAllocator: Allocator, alloc: Allocator, pair: Pair, newItem: T) !bool {
            std.log.info("Adding to dic new char for domain {x}", .{newItem});

            var buffer: [BufferLen]u8 = undefined;
            var list = std.ArrayList(u8).initBuffer(&buffer);

            var current = self.dic;
            itemToSlice(&self.revDic, &list, pair.l);

            for (list.items) |item| {
                current = try current.insertChar(arenaAllocator, item);
                if (current.getPtrValue()) |v| v.min = @min(newItem, v.min) else current.setValue(.{ .min = newItem });
            }

            list.clearRetainingCapacity();

            itemToSlice(&self.revDic, &list, pair.r);

            for (list.items) |item| {
                current = try current.insertChar(arenaAllocator, item);
                if (current.getPtrValue()) |v| v.min = @min(newItem, v.min) else current.setValue(.{ .min = newItem });
            }

            const rightValue = current.getPtrValue().?;
            assert(rightValue.parent == null or rightValue.parent.? == pair.r);
            if (pair.r >= math.maxInt(u8) and rightValue.parent == null) current.getPtrValue().?.*.parent = pair.r;

            try self.revDic.put(alloc, newItem, pair);
            current.getPtrValue().?.value = newItem;

            return self.newItem == math.maxInt(T);
        }

        fn itemToSlice(revDic: *const RevDic, list: *std.ArrayList(u8), item: T) void {
            if (item <= math.maxInt(u8)) {
                list.appendAssumeCapacity(@intCast(item));
            } else {
                const pair = revDic.get(item).?;
                itemToSlice(revDic, list, pair.l);
                itemToSlice(revDic, list, pair.r);
            }
        }

        pub fn iterate(self: *Self, alloc: Allocator, pairToChange: Pair, newItem: T) !void {
            std.log.info("Logically Replacing {f} with {x}", .{ pairToChange, newItem });

            var timer: ?std.time.Timer = null;

            if (build_options.bench) {
                timer = try std.time.Timer.start();
            }

            const ctx: Pair.Context = .{};

            var buffer: [BufferLen]u8 = undefined;
            var readerIO = self.file.reader(&buffer);
            const reader = &readerIO.interface;

            var before: ?T = null;
            var l: ?T = try getToken(self.dic, reader);
            while (l) |left| {
                const r = try getToken(self.dic, reader) orelse break;
                const current = Pair.init(left, r);

                if (ctx.eql(current, pairToChange)) {
                    if (before) |b| {
                        const decrement = Pair.init(b, left);
                        self.count.getPtr(decrement).?.* -= 1;

                        const toInsert = Pair.init(b, newItem);
                        if (self.count.getPtr(toInsert)) |value|
                            value.* += 1
                        else
                            try self.count.put(alloc, toInsert, 1);
                    }

                    if (self.count.getPtr(current)) |count| count.* -= 1;

                    const after = try getToken(self.dic, reader);

                    if (after) |a| {
                        const decrement = Pair.init(r, a);
                        self.count.getPtr(decrement).?.* -= 1;

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

            assert(self.count.get(pairToChange).? == 0);

            if (build_options.bench) {
                std.log.debug("It took {}s", .{@as(f64, @floatFromInt(timer.?.lap())) / std.time.ns_per_s});
            }

            var tryAgain = true;
            var buff: [20]Pair = undefined;
            var list: std.ArrayList(Pair) = .initBuffer(&buff);
            while (tryAgain) {
                defer list.clearRetainingCapacity();
                var it = self.count.iterator();

                while (it.next()) |e| {
                    if (e.value_ptr.* == 0) list.appendBounded(e.key_ptr.*) catch break;
                } else {
                    tryAgain = false;
                }

                for (list.items) |v| {
                    _ = self.count.remove(v);
                }
            }

            self.count.rehash(Pair.Context{});

            // WARN: Printing the counting the quantity of pairs is a little more dificult
            std.log.info("Resulting dic with {} unique pairs", .{self.count.count()});
        }

        fn getToken(dic: *Dic, r: *io.Reader) !?T {
            var checkPoint: struct { item: T, depth: usize } = .{ .item = try peekByte(r, 0) orelse return null, .depth = 0 };
            defer r.toss(checkPoint.depth + 1);

            var child = dic.getChar(@intCast(checkPoint.item)) orelse return checkPoint.item;
            var depth: usize = 1;
            while (try peekByte(r, depth)) |peeked| : (depth += 1) {
                child = child.getChar(peeked) orelse break;

                const value = child.getValue().?;
                if (value.value) |v| {
                    if (try validToken(dic, r, v, value.parent, checkPoint.depth + 1, depth + 1)) checkPoint = .{ .item = v, .depth = depth };
                }
            }

            return checkPoint.item;
        }

        fn validToken(dic: *Dic, r: *io.Reader, value: T, _parent: ?T, startingDepth: usize, maxDepth: usize) !bool {
            var toChange = _parent orelse value;
            var limit = value;
            var depth: usize = startingDepth;

            while (depth < maxDepth) : (depth += 1) {
                var child = dic.getChar(try peekByte(r, depth) orelse unreachable) orelse continue;
                var checkPointDepth = depth;
                var innerDepth = checkPointDepth + 1;

                if (child.getValue().?.min > limit) continue;

                while (try peekByte(r, innerDepth)) |peeked| : (innerDepth += 1) {
                    child = child.getChar(peeked) orelse break;

                    const childValue = child.getValue().?;
                    if (childValue.min > limit) break;
                    if (childValue.value) |v| {
                        if (innerDepth == maxDepth - 1) toChange = childValue.parent orelse toChange;
                        if (v < limit) {
                            if (innerDepth >= maxDepth and !try validToken(dic, r, v, childValue.parent, checkPointDepth + 1, innerDepth + 1)) continue;
                            checkPointDepth = innerDepth;
                        }
                    }
                }

                if (checkPointDepth >= maxDepth) return false;
                limit = toChange;
            }

            return true;
        }

        fn peekByte(r: *io.Reader, n: usize) !?u8 {
            assert(n + 1 < BufferLen);
            const buf = r.peek(n + 1) catch |err| switch (err) {
                error.ReadFailed => return err,
                error.EndOfStream => return null,
            };

            return buf[n];
        }

        pub fn verifyCount(self: *Self, alloc: Allocator) !void {
            var buffer: [BufferLen]u8 = undefined;
            var readerIO = self.file.reader(&buffer);
            const reader = &readerIO.interface;
            var actual = PairCounting.empty;
            defer actual.deinit(alloc);
            try actual.ensureTotalCapacity(alloc, self.count.count());

            var before: T = try getToken(self.dic, reader) orelse unreachable;
            while (try getToken(self.dic, reader)) |r| {
                const toInsert = Pair.init(before, r);
                defer before = toInsert.r;

                if (actual.getPtr(toInsert)) |value|
                    value.* += 1
                else
                    try actual.put(alloc, toInsert, 1);
            }

            var allMatch = true;

            var selfIt = self.count.iterator();
            while (selfIt.next()) |entry| {
                const expectedCount = entry.value_ptr.*;
                if (actual.get(entry.key_ptr.*)) |actualCount| {
                    if (expectedCount != actualCount) {
                        std.log.err("Mismatch for pair {f}: expected {}, got {}", .{ entry.key_ptr.*, expectedCount, actualCount });
                        allMatch = false;
                    }
                } else {
                    std.log.err("Pair {f} expected with count {} but not found in actual", .{ entry.key_ptr.*, expectedCount });
                    allMatch = false;
                }
            }

            var actualIt = actual.iterator();
            while (actualIt.next()) |entry| {
                if (!self.count.contains(entry.key_ptr.*)) {
                    std.log.err("Pair {f} found in actual with count {} but not in expected", .{ entry.key_ptr.*, entry.value_ptr.* });
                    allMatch = false;
                }
            }

            if (!allMatch) std.debug.panic("Failed", .{});
            std.log.info("Count verification passed: {} unique pairs match", .{self.count.count()});
        }

        pub fn printCount(self: *const Self) !void {
            std.log.info("Printing Dictionay", .{});
            var buffer: [BufferLen]u8 = undefined;
            const stderr = std.fs.File.stdout();
            var writerIO = stderr.writer(&buffer);

            const w = &writerIO.interface;
            defer w.flush() catch @panic("Failed to print dic state\n");

            _ = try w.write("Resulting Count:\n");
            var it = self.count.iterator();
            while (it.next()) |t| {
                _ = try w.write("\t (");

                if (t.key_ptr.l <= math.maxInt(u8))
                    try w.writeByte(@intCast(t.key_ptr.l))
                else
                    try w.print("{x}", .{t.key_ptr.l});

                _ = try w.write(", ");

                if (t.key_ptr.r <= math.maxInt(u8))
                    try w.writeByte(@intCast(t.key_ptr.r))
                else
                    try w.print("{x}", .{t.key_ptr.r});

                try w.print(") => {}\n", .{t.value_ptr.*});
            }
        }

        pub fn printDic(self: *const Self) !void {
            std.log.info("Printing Dictionay", .{});
            var buffer: [BufferLen]u8 = undefined;
            const stderr = std.fs.File.stdout();
            var writerIO = stderr.writer(&buffer);

            const w = &writerIO.interface;
            defer w.flush() catch @panic("Failed to print dic state\n");

            _ = try w.write("Resulting Dic:\n");
            try self.dic.prettyPrint(w);
        }

        pub fn printText(self: *const Self) !void {
            std.log.info("Printing Text", .{});
            var bufferStdOut: [BufferLen]u8 = undefined;
            const stderr = std.fs.File.stdout();
            var writerIO = stderr.writer(&bufferStdOut);

            var bufferReader: [BufferLen]u8 = undefined;
            var readerIO = self.file.reader(&bufferReader);
            const reader = &readerIO.interface;

            const w = &writerIO.interface;
            defer w.flush() catch @panic("Failed to print dic state\n");

            while (try getToken(self.dic, reader)) |t| {
                try if (t < math.maxInt(u8))
                    w.writeByte(@intCast(t))
                else
                    w.print("<{x}>", .{t});
            }
        }
    };
}

test {
    _ = @import("Trie.zig");
}

const Trie = @import("Trie.zig").Trie;

const std = @import("std");
const build_options = @import("build_options");

const Allocator = std.mem.Allocator;
const Order = std.math.Order;
const File = std.fs.File;
const Timer = std.time.Timer;
const io = std.io;
const math = std.math;
const assert = std.debug.assert;
