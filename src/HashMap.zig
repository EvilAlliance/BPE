const Hash = usize;

// This was based in zig hash map I may be smart enough to do it alone, but I want to advace further
// There will be another feature and may be change differently
pub fn HashMap(comptime K: type, comptime V: type, comptime Context: type, comptime loadFactor: comptime_int) type {
    if (loadFactor >= 100) @compileError("Load factor is a persentage");

    if (@sizeOf(Context) != 0)
        @compileError("Cannot infer context " ++ @typeName(Context) ++ ", call putContext instead.");
    return struct {
        const Self = @This();
        const Size = u32;

        const GroupSize: u8 = 8;
        const RobinHood = u8;
        const MinSize = 8;
        comptime {
            assert(@sizeOf(Metadata) == @sizeOf(RobinHood) and @sizeOf(RobinHood) == 1);
            assert(std.math.isPowerOfTwo(GroupSize));
            assert(MinSize >= GroupSize);
        }

        const Header = struct {
            keys: [*]K,
            values: [*]V,
            capacity: Size,
        };

        const Entry = struct {
            key: *K,
            value: *V,
        };

        // [Header][Metadata][Keys][Values]
        //         ^ Here is metadata pointing at
        // Metadata is divided by [8*Metadata][8*RobingHood]
        metadata: ?[*]Metadata = null,

        available: Size = 0,
        size: Size = 0,

        fn deinit(self: *Self, alloc: Allocator) void {
            self.deallocate(alloc);
            self.* = undefined;
        }

        fn deallocate(self: *Self, alloc: Allocator) void {
            if (self.metadata == null) return;

            const headerAlign = @alignOf(Header);
            const keyAlign = if (@sizeOf(K) == 0) 1 else @alignOf(K);
            const valAlign = if (@sizeOf(V) == 0) 1 else @alignOf(V);
            const vectorAlign = @alignOf(@Vector(GroupSize, u8));
            const maxAlign = comptime @max(headerAlign, keyAlign, valAlign, vectorAlign);

            const newCap: usize = self.capacity();
            const metaStart = std.mem.alignForward(usize, @sizeOf(Header), vectorAlign);
            const metaSize = metaStart + newCap * @sizeOf(Metadata) * 2;
            comptime assert(@alignOf(Metadata) == 1);

            const keysStart = std.mem.alignForward(usize, metaSize, keyAlign);
            const keysEnd = keysStart + newCap * @sizeOf(K);

            const valsStart = std.mem.alignForward(usize, keysEnd, valAlign);
            const valsEnd = valsStart + newCap * @sizeOf(V);

            const slice = @as([*]align(maxAlign) u8, @ptrCast(@alignCast(self.header())))[0..valsEnd];
            alloc.free(slice);

            self.metadata = null;
            self.available = 0;
        }

        fn header(self: Self) *Header {
            return @ptrCast(@as([*]Header, @ptrCast(@alignCast(self.metadata.?))) - 1);
        }

        pub fn keys(self: *Self) [*]K {
            return self.header().keys;
        }

        pub fn values(self: *Self) [*]V {
            return self.header().values;
        }

        pub fn capacity(self: Self) Size {
            if (self.metadata == null) return 0;

            return self.header().capacity;
        }

        fn load(self: *Self) Size {
            const max_load = (self.capacity() * loadFactor) / 100;
            assert(max_load >= self.available);
            return @as(Size, @truncate(max_load - self.available));
        }

        pub fn ensureTotalCapacity(self: *Self, alloc: Allocator, newCapacity: Size) !void {
            _ = .{ self, alloc, newCapacity };
            if (newCapacity > self.size)
                try self.growIfNeeded(alloc, newCapacity - self.size, undefined);
        }

        fn growIfNeeded(self: *Self, alloc: Allocator, newCount: Size, ctx: Context) (Allocator.Error || error{Overflow})!void {
            if (newCount > self.available) {
                try self.grow(alloc, capacityForSize(self.load() + newCount), ctx);
            }
        }

        fn grow(self: *Self, alloc: Allocator, newCapacity: Size, ctx: Context) (Allocator.Error || error{Overflow})!void {
            assert(newCapacity > self.capacity());
            assert(std.math.isPowerOfTwo(newCapacity));

            var map = Self{};
            try map.allocate(alloc, newCapacity);
            map.initMetadata();
            map.available = @truncate((newCapacity * loadFactor) / 100);

            if (self.size != 0) {
                const oldCapacity = self.capacity();
                for (
                    self.metadata.?[0..oldCapacity],
                    self.keys()[0..oldCapacity],
                    self.values()[0..oldCapacity],
                ) |m, k, v| {
                    _ = ctx;
                    if (!m.isUsed()) continue;
                    try map.put(alloc, k, v);
                    if (map.size == self.size) break;
                }
            }

            self.size = 0;
            std.mem.swap(Self, self, &map);
            map.deinit(alloc);
        }

        fn initMetadata(self: *Self) void {
            @memset(@as([*]u8, @ptrCast(self.metadata.?))[0 .. @sizeOf(Metadata) * self.capacity() * 2], 0);
        }

        fn allocate(self: *Self, alloc: Allocator, newCapacity: Size) Allocator.Error!void {
            const headerAlign = @alignOf(Header);
            const keyAlign = if (@sizeOf(K) == 0) 1 else @alignOf(K);
            const valAlign = if (@sizeOf(V) == 0) 1 else @alignOf(V);
            const maxAlign: std.mem.Alignment = comptime .fromByteUnits(@max(headerAlign, keyAlign, valAlign));

            const newCap: usize = newCapacity;
            const metaSize = @sizeOf(Header) + newCap * @sizeOf(Metadata) * 2;
            comptime assert(@alignOf(Metadata) == 1);

            const keysStart = std.mem.alignForward(usize, metaSize, keyAlign);
            const keysEnd = keysStart + newCap * @sizeOf(K);

            const valsStart = std.mem.alignForward(usize, keysEnd, valAlign);
            const valsEnd = valsStart + newCap * @sizeOf(V);

            const totalSize = maxAlign.forward(valsEnd);

            const slice = try alloc.alignedAlloc(u8, maxAlign, totalSize);
            const ptr: [*]u8 = @ptrCast(slice.ptr);

            const metadata = ptr + @sizeOf(Header);
            const hdr = @as(*Header, @ptrCast(@alignCast(ptr)));

            assert(@sizeOf([*]V) != 0);
            assert(@sizeOf([*]K) != 0);

            hdr.values = @ptrCast(@alignCast((ptr + valsStart)));
            hdr.keys = @ptrCast(@alignCast((ptr + keysStart)));

            hdr.capacity = newCapacity;
            self.metadata = @ptrCast(@alignCast(metadata));
        }

        fn capacityForSize(size: Size) Size {
            var newCap: Size = @intCast((@as(u64, size) * 100) / loadFactor + 1);
            newCap = std.math.ceilPowerOfTwo(Size, newCap) catch unreachable;
            return @max(MinSize, newCap);
        }

        pub fn put(self: *Self, alloc: Allocator, key: K, value: V) (Allocator.Error || error{Overflow})!void {
            const ctx: Context = undefined;
            try self.growIfNeeded(alloc, 1, ctx);

            const hash: Hash = ctx.hash(key);
            const mask = (self.capacity() - 1) ^ 0b111;
            var limit = @ctz(self.capacity());

            var idx: usize = @truncate(hash & mask);

            const fingerprint = Metadata.takeFingerprint(hash);
            var expected: Metadata = .{};
            expected.fill(fingerprint);
            var firstTombStone: struct { index: usize = 0, robinHood: u6 = 0 } = .{};
            var firstRobinHood: struct { index: usize = 0, robinHood: u6 = 0 } = .{};

            while (limit != 0) : (limit -= 1) {
                const startMetadataGroup = self.metadata.? + idx;
                const startRobinHoodGroup = self.metadata.? + idx + GroupSize;

                const vecRobinHood: @Vector(GroupSize, u8) = @bitCast(startRobinHoodGroup[0..GroupSize].*);
                const robinHood: u8 = @bitCast(vecRobinHood > @as(@Vector(GroupSize, u8), @splat(limit)));

                const vecMetadata: @Vector(GroupSize, u8) = @bitCast(startMetadataGroup[0..GroupSize].*);
                var equalExpected: u8 = @bitCast(vecMetadata == @as(@Vector(GroupSize, u8), @splat(@bitCast(expected))));
                const equalTombstone: u8 = @bitCast(vecMetadata == @as(@Vector(GroupSize, u8), @splat(@bitCast(Metadata.tombstoneSlote))));
                const equalFree: u8 = @bitCast(vecMetadata == @as(@Vector(GroupSize, u8), @splat(@bitCast(Metadata.freeSlote))));

                if (equalTombstone != 0) {
                    if (firstTombStone.robinHood == 0) firstTombStone = .{ .index = idx + @ctz(equalTombstone), .robinHood = limit };
                }

                if (robinHood != 0) {
                    if (firstRobinHood.robinHood == 0) firstRobinHood = .{ .index = idx + @ctz(robinHood), .robinHood = limit };
                }

                while (equalExpected != 0) {
                    const offset = @ctz(equalExpected);
                    const index = idx + offset;

                    if (ctx.eql(self.keys()[index], key)) {
                        self.values()[index] = value;
                        return;
                    }

                    equalExpected ^= std.math.shl(u8, 1, offset);
                }

                if (equalFree != 0) {
                    if (firstRobinHood.robinHood != 0 or firstTombStone.robinHood != 0) break;
                    const offset = @ctz(equalFree);
                    const index = idx + offset;

                    self.metadata.?[index].fill(fingerprint);
                    self.metadata.?[self.capacity() + index].robinHood(limit);
                    self.keys()[index] = key;
                    self.values()[index] = value;

                    self.size += 1;
                    self.available -= 1;

                    return;
                }

                idx = (idx + 2 * GroupSize) & mask;
            }

            if (firstTombStone.robinHood != 0) {
                self.metadata.?[firstTombStone.index].fill(fingerprint);
                self.metadata.?[self.capacity() + firstTombStone.index].robinHood(firstTombStone.robinHood);
                self.keys()[firstTombStone.index] = key;
                self.values()[firstTombStone.index] = value;

                self.size += 1;
                self.available -= 1;

                return;
            }

            if (firstRobinHood.robinHood != 0) {
                self.metadata.?[firstRobinHood.index].fill(fingerprint);
                self.metadata.?[self.capacity() + firstRobinHood.index].robinHood(firstRobinHood.robinHood);

                const oldK = self.keys()[firstRobinHood.index];
                const oldV = self.values()[firstRobinHood.index];

                self.keys()[firstRobinHood.index] = key;
                self.values()[firstRobinHood.index] = value;

                // TODO: Create a put with assume capacity and no duplicate key
                try self.put(alloc, oldK, oldV);

                return;
            }

            if (limit == 0) {
                try self.grow(alloc, try std.math.ceilPowerOfTwo(Size, self.capacity() + 1), ctx);

                // TODO: Create a put with assume capacity and no duplicate key
                try self.put(alloc, key, value);
            }
        }

        pub fn getOrPutValue(self: *Self, alloc: Allocator, key: K, value: V) !Entry {
            const ctx: Context = undefined;
            try self.growIfNeeded(alloc, 1, ctx);

            const hash: Hash = ctx.hash(key);
            const mask = (self.capacity() - 1) ^ 0b1111;
            var limit = @ctz(self.capacity());

            // Divide by group
            var idx: usize = @truncate(hash & mask);

            const fingerprint = Metadata.takeFingerprint(hash);
            var expected: Metadata = .{};
            expected.fill(fingerprint);
            var firstTombStone: struct { index: usize = 0, robinHood: u6 = 0 } = .{};
            var firstRobinHood: struct { index: usize = 0, robinHood: u6 = 0 } = .{};

            while (limit != 0) : (limit -= 1) {
                const startMetadataGroup = self.metadata.? + idx;
                const startRobinHoodGroup = self.metadata.? + idx + GroupSize;

                const vecRobinHood: @Vector(GroupSize, u8) = @bitCast(startRobinHoodGroup[0..GroupSize].*);
                const robinHood: u8 = @bitCast(vecRobinHood > @as(@Vector(GroupSize, u8), @splat(limit)));

                const vecMetadata: @Vector(GroupSize, u8) = @bitCast(startMetadataGroup[0..GroupSize].*);
                var equalExpected: u8 = @bitCast(vecMetadata == @as(@Vector(GroupSize, u8), @splat(@bitCast(expected))));
                const equalTombstone: u8 = @bitCast(vecMetadata == @as(@Vector(GroupSize, u8), @splat(@bitCast(Metadata.tombstoneSlote))));
                const equalFree: u8 = @bitCast(vecMetadata == @as(@Vector(GroupSize, u8), @splat(@bitCast(Metadata.freeSlote))));

                if (equalTombstone != 0) {
                    if (firstTombStone.robinHood == 0) firstTombStone = .{ .index = idx + @ctz(equalTombstone), .robinHood = limit };
                }

                if (robinHood != 0) {
                    if (firstRobinHood.robinHood == 0) firstRobinHood = .{ .index = idx + @ctz(robinHood), .robinHood = limit };
                }

                while (equalExpected != 0) {
                    const offset = @ctz(equalExpected);
                    const index = idx + offset;
                    const storedKey = self.keys()[index];

                    if (ctx.eql(storedKey, key)) {
                        return .{ .key = &self.keys()[index], .value = &self.values()[index] };
                    }

                    equalExpected ^= std.math.shl(u8, 1, offset);
                }

                if (equalFree != 0) {
                    if (firstRobinHood.robinHood != 0 or firstTombStone.robinHood != 0) break;
                    const offset = @ctz(equalFree);
                    const index = idx + offset;

                    self.metadata.?[index].fill(fingerprint);
                    self.metadata.?[self.capacity() + index].robinHood(limit);
                    self.keys()[index] = key;
                    self.values()[index] = value;

                    self.size += 1;
                    self.available -= 1;

                    return .{ .key = &self.keys()[index], .value = &self.values()[index] };
                }

                idx = (idx + 2 * GroupSize) & mask;
            }

            if (firstTombStone.robinHood != 0) {
                self.metadata.?[firstTombStone.index].fill(fingerprint);
                self.metadata.?[self.capacity() + firstTombStone.index].robinHood(firstTombStone.robinHood);
                self.keys()[firstTombStone.index] = key;
                self.values()[firstTombStone.index] = value;

                self.size += 1;
                self.available -= 1;

                return .{ .key = &self.keys()[firstTombStone.index], .value = &self.values()[firstTombStone.index] };
            }

            if (firstRobinHood.robinHood != 0) {
                self.metadata.?[firstRobinHood.index].fill(fingerprint);
                self.metadata.?[self.capacity() + firstRobinHood.index].robinHood(firstRobinHood.robinHood);

                const oldK = self.keys()[firstRobinHood.index];
                const oldV = self.values()[firstRobinHood.index];

                self.keys()[firstRobinHood.index] = key;
                self.values()[firstRobinHood.index] = value;

                // TODO: Create a put with assume capacity and no duplicate key
                try self.put(alloc, oldK, oldV);

                return .{ .key = &self.keys()[firstRobinHood.index], .value = &self.values()[firstRobinHood.index] };
            }

            if (limit == 0) {
                const newCapacity = std.math.mul(Size, self.capacity(), 2) catch return error.Overflow;
                try self.grow(alloc, newCapacity, ctx);

                // TODO: Create a put with assume capacity and no duplicate key
                return try self.getOrPutValue(alloc, key, value);
            }

            unreachable;
        }

        pub fn get(self: *Self, key: K) ?V {
            const ctx: Context = undefined;

            const hash: Hash = ctx.hash(key);
            const mask = (self.capacity() - 1) ^ 0b1111;
            var limit = @ctz(self.capacity());

            var idx: usize = @truncate(hash & mask);

            const fingerprint = Metadata.takeFingerprint(hash);
            var expected: Metadata = .{};
            expected.fill(fingerprint);

            while (limit != 0) : (limit -= 1) {
                const startMetadataGroup = self.metadata.? + idx;

                const vecMetadata: @Vector(GroupSize, u8) = @bitCast(startMetadataGroup[0..GroupSize].*);
                var equalExpected: u8 = @bitCast(vecMetadata == @as(@Vector(GroupSize, u8), @splat(@bitCast(expected))));

                while (equalExpected != 0) {
                    const offset = @ctz(equalExpected);
                    const index = idx + offset;

                    if (ctx.eql(self.keys()[index], key)) {
                        return self.values()[index];
                    }

                    equalExpected ^= std.math.shl(u8, 1, offset);
                }

                const equalFree: u8 = @bitCast(vecMetadata == @as(@Vector(GroupSize, u8), @splat(@bitCast(Metadata.freeSlote))));
                if (equalFree != 0) break;

                idx = (idx + 2 * GroupSize) & mask;
            }
            return null;
        }

        pub fn count(self: *const Self) Size {
            return self.size;
        }
    };
}

const Metadata = packed struct {
    const FingerPrint = u7;

    const free: FingerPrint = 0;
    const tombstone: FingerPrint = 1;

    fingerPrint: FingerPrint = free,
    used: u1 = 0,

    const freeSlote = @as(u8, @bitCast(Metadata{ .fingerPrint = free }));
    const tombstoneSlote = @as(u8, @bitCast(Metadata{ .fingerPrint = tombstone }));

    pub fn isUsed(self: Metadata) bool {
        return self.used == 1;
    }

    pub fn isTombstone(self: Metadata) bool {
        return @as(u8, @bitCast(self)) == tombstoneSlote;
    }

    pub fn isFree(self: Metadata) bool {
        return @as(u8, @bitCast(self)) == freeSlote;
    }

    pub fn takeFingerprint(hash: Hash) FingerPrint {
        const hashBits = @typeInfo(Hash).int.bits;
        const fpBits = @typeInfo(FingerPrint).int.bits;
        return @as(FingerPrint, @truncate(hash >> (hashBits - fpBits)));
    }

    pub fn fill(self: *Metadata, fp: FingerPrint) void {
        self.used = 1;
        self.fingerPrint = fp;
    }

    pub fn remove(self: *Metadata) void {
        self.used = 0;
        self.fingerPrint = tombstone;
    }

    pub fn robinHood(self: *Metadata, rb: u6) void {
        self.used = 0;
        self.fingerPrint = @intCast(rb);
    }
};

comptime {
    assert(@sizeOf(Metadata) == 1);
    assert(@alignOf(Metadata) == 1);
}

const std = @import("std");

const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

// pub fn main() !void {
//     var dic: HashMap(u32, u32, struct {
//         pub fn hash(_: @This(), p: u32) usize {
//             var x: usize = @as(usize, @intCast(p)) | (@as(usize, @intCast(p)) << 16) | (@as(usize, @intCast(p)) << 32) | (@as(usize, @intCast(p)) << 48);
//             x ^= x >> 33;
//             x *%= 0xff51afd7ed558ccd;
//             x ^= x >> 33;
//             x *%= 0xc4ceb9fe1a85ec53;
//             x ^= x >> 33;
//             return x;
//         }
//         pub fn eql(_: @This(), a: u32, b: u32) bool {
//             return a == b;
//         }
//     }, 50) = .{};
//
//     try dic.put(std.heap.page_allocator, 1, 10);
//     std.log.debug("{?}", .{dic.get(1)});
// }
