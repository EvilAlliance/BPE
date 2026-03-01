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

        const GroupSize: Size = 8;
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

        const Slot = struct {
            key: *K,
            value: *V,
            existed: bool,
        };

        // [Header][Metadata][Keys][Values]
        //         ^ Here is metadata pointing at
        // Metadata is divided by [8*Metadata][8*RobingHood]
        metadata: ?[*]Metadata = null,

        available: Size = 0,
        size: Size = 0,

        pub fn deinit(self: *Self, alloc: Allocator) void {
            self.deallocate(alloc);
            self.* = undefined;
        }

        //////////////////////////////////////////////////////////////////////////////////////////////////////
        //                                             Allocation
        //////////////////////////////////////////////////////////////////////////////////////////////////////
        fn deallocate(self: *Self, alloc: Allocator) void {
            if (self.metadata == null) return;

            const headerAlign = @alignOf(Header);
            const keyAlign = if (@sizeOf(K) == 0) 1 else @alignOf(K);
            const valAlign = if (@sizeOf(V) == 0) 1 else @alignOf(V);
            const maxAlign = comptime @max(headerAlign, keyAlign, valAlign);

            const newCap: usize = self.capacity();
            const metaSize = @sizeOf(Header) + newCap * @sizeOf(Metadata); // * 2;
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

        fn allocate(self: *Self, alloc: Allocator, newCapacity: Size) Allocator.Error!void {
            const headerAlign = @alignOf(Header);
            const keyAlign = if (@sizeOf(K) == 0) 1 else @alignOf(K);
            const valAlign = if (@sizeOf(V) == 0) 1 else @alignOf(V);
            const maxAlign: std.mem.Alignment = comptime .fromByteUnits(@max(headerAlign, keyAlign, valAlign));

            const newCap: usize = newCapacity;
            const metaSize = @sizeOf(Header) + newCap * @sizeOf(Metadata); // * 2;
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

        fn initMetadata(self: *Self) void {
            @memset(@as([*]u8, @ptrCast(self.metadata.?))[0 .. @sizeOf(Metadata) * self.capacity()], 0);
        }

        //////////////////////////////////////////////////////////////////////////////////////////////////////
        //                                              Helpers
        //////////////////////////////////////////////////////////////////////////////////////////////////////
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

        //////////////////////////////////////////////////////////////////////////////////////////////////////
        //                                             Grow Utils
        //////////////////////////////////////////////////////////////////////////////////////////////////////
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
                // var idx: usize = 0;
                // blk: while (idx < oldCapacity * 2) : (idx += 2 * GroupSize) {
                //     for (
                //         self.metadata.?[idx .. idx + GroupSize],
                //         self.keys()[idx .. idx + GroupSize],
                //         self.values()[idx .. idx + GroupSize],
                //     ) |m, k, v| {
                //         _ = ctx;
                //         if (!m.isUsed()) continue;
                //         try map.put(alloc, k, v);
                //         if (map.size == self.size) break :blk;
                //     }
                // }

                for (
                    self.metadata.?[0..oldCapacity],
                    self.keys()[0..oldCapacity],
                    self.values()[0..oldCapacity],
                ) |m, k, v| {
                    _ = ctx;
                    if (!m.isUsed()) continue;
                    try map.put(alloc, k, v);
                }
            }

            std.mem.swap(Self, self, &map);
            map.size = 0;
            map.deinit(alloc);
        }

        fn capacityForSize(size: Size) Size {
            var newCap: Size = @intCast((@as(u64, size) * 100) / loadFactor + 1);
            newCap = std.math.ceilPowerOfTwo(Size, newCap) catch unreachable;
            return @max(MinSize, newCap);
        }

        //////////////////////////////////////////////////////////////////////////////////////////////////////
        //                                               Utils
        //////////////////////////////////////////////////////////////////////////////////////////////////////
        const GetSlotOptions = struct {
            search: bool = true,
            insert: bool = true,
        };

        fn getSlot(self: *Self, comptime options: GetSlotOptions, alloc: if (options.insert) Allocator else void, key: K, ctx: anytype) if (options.insert) (Allocator.Error || error{Overflow})!Slot else ?Slot {
            const hash: Hash = ctx.hash(key);
            const mask = (self.capacity() - 1) & comptime ~(GroupSize - 1);
            var limit: u32 = @ctz(self.capacity()) >> comptime @ctz(GroupSize);
            var idx: usize = @truncate(hash & mask);

            const fingerprint = Metadata.takeFingerprint(hash);
            var expected: Metadata = .{};
            expected.fill(fingerprint);

            var insertMeta: ?[*]Metadata = null;
            var insertSlot: Slot = undefined;

            while (limit != 0) : (limit -= 1) {
                const startMetadataGroup = self.metadata.? + idx;
                const vecMetadata: @Vector(GroupSize, u8) = @bitCast(startMetadataGroup[0..GroupSize].*);

                if (options.search) {
                    var equalExpected: u8 = @bitCast(vecMetadata == @as(@Vector(GroupSize, u8), @splat(@bitCast(expected))));
                    while (equalExpected != 0) {
                        const offset = @ctz(equalExpected);
                        const index = idx + offset;
                        if (ctx.eql(self.keys()[index], key)) {
                            return .{ .existed = true, .key = &self.keys()[index], .value = &self.values()[index] };
                        }
                        equalExpected &= ~std.math.shl(u8, 1, offset);
                    }
                }

                const equalFree: u8 = @bitCast(vecMetadata == @as(@Vector(GroupSize, u8), @splat(@bitCast(Metadata.freeSlote))));

                if (options.insert) {
                    const equalTombstone: u8 = @bitCast(vecMetadata == @as(@Vector(GroupSize, u8), @splat(@bitCast(Metadata.tombstoneSlote))));
                    if (insertMeta == null and (equalTombstone | equalFree) != 0) {
                        const index = idx + @ctz(equalTombstone | equalFree);
                        insertMeta = self.metadata.? + index;
                        insertSlot = .{ .existed = false, .key = &self.keys()[index], .value = &self.values()[index] };
                    }
                }

                if (equalFree != 0) break;
                idx = (idx + GroupSize) & mask;
            }

            if (options.insert) {
                const meta = insertMeta orelse {
                    assert(limit == 0);
                    try self.grow(alloc, capacityForSize(self.capacity() + 1), ctx);
                    return try self.getSlot(options, alloc, key, ctx);
                };

                meta[0].fill(fingerprint);
                self.available -= 1;
                self.size += 1;

                return insertSlot;
            } else {
                return null;
            }
        }

        inline fn findSlot(self: *Self, key: K, ctx: anytype) ?Slot {
            return self.getSlot(.{ .insert = false }, {}, key, ctx);
        }

        inline fn getOrPutSlot(self: *Self, alloc: Allocator, key: K, ctx: anytype) (Allocator.Error || error{Overflow})!Slot {
            return self.getSlot(.{}, alloc, key, ctx);
        }

        inline fn putSlot(self: *Self, alloc: Allocator, key: K, ctx: anytype) (Allocator.Error || error{Overflow})!Slot {
            return self.getSlot(.{ .search = false }, alloc, key, ctx);
        }

        pub fn ensureTotalCapacity(self: *Self, alloc: Allocator, newCapacity: Size) !void {
            if (newCapacity > self.size)
                try self.growIfNeeded(alloc, newCapacity - self.size, undefined);
        }

        pub fn put(self: *Self, alloc: Allocator, key: K, value: V) (Allocator.Error || error{Overflow})!void {
            const ctx: Context = undefined;
            try self.growIfNeeded(alloc, 1, ctx);
            const slot = try self.getOrPutSlot(alloc, key, ctx);

            if (!slot.existed) {
                slot.key.* = key;
            }

            slot.value.* = value;
        }

        pub fn getOrPutValue(self: *Self, alloc: Allocator, key: K, value: V) !Entry {
            const ctx: Context = undefined;
            try self.growIfNeeded(alloc, 1, ctx);
            const slot = try self.getOrPutSlot(alloc, key, ctx);

            if (!slot.existed) {
                slot.key.* = key;
                slot.value.* = value;
            }

            return .{
                .key = slot.key,
                .value = slot.value,
            };
        }

        pub fn get(self: *Self, key: K) ?V {
            const ctx: Context = undefined;
            const slot = self.findSlot(key, ctx) orelse return null;
            return slot.value.*;
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

test "HashMap Stress Test" {
    const alloc = std.testing.allocator;

    const Context = struct {
        pub fn hash(_: @This(), k: u32) usize {
            var x: usize = @as(usize, k);
            x ^= x >> 16;
            x *%= 0x21f0aaad;
            x ^= x >> 15;
            x *%= 0x735a2d97;
            x ^= x >> 15;
            return x;
        }
        pub fn eql(_: @This(), a: u32, b: u32) bool {
            return a == b;
        }
    };

    var map = HashMap(u32, u32, Context, 75){};
    defer map.deinit(alloc);

    std.debug.print("\n=== HashMap Stress Test ===\n", .{});

    // Test 1: Insert 1 million entries
    std.debug.print("Test 1: Inserting 1,000,000 entries...\n", .{});
    var i: u32 = 0;
    while (i < 1_000_000) : (i += 1) {
        try map.put(alloc, i, i * 2);
        if (i % 100_000 == 0 and i > 0) {
            std.debug.print("  Inserted {d} entries, size={d}, capacity={d}\n", .{ i, map.count(), map.capacity() });
        }
    }
    std.debug.print("  Final size={d}, capacity={d}\n", .{ map.count(), map.capacity() });

    // Test 2: Verify all entries exist
    std.debug.print("Test 2: Verifying all entries...\n", .{});
    i = 0;
    while (i < 1_000_000) : (i += 1) {
        const val = map.get(i);
        try std.testing.expect(val != null);
        try std.testing.expectEqual(i * 2, val.?);
    }
    std.debug.print("  All 1,000,000 entries verified!\n", .{});

    // Test 3: Update using getOrPutValue
    std.debug.print("Test 3: Updating entries with getOrPutValue...\n", .{});
    i = 0;
    while (i < 1_000_000) : (i += 1) {
        const entry = try map.getOrPutValue(alloc, i, 0);
        entry.value.* += 100; // Add 100 to existing value
        if (i % 100_000 == 0 and i > 0) {
            std.debug.print("  Updated {d} entries\n", .{i});
        }
    }

    // Test 4: Verify updates via getOrPutValue
    std.debug.print("Test 4: Verifying getOrPutValue updates...\n", .{});
    i = 0;
    while (i < 1_000_000) : (i += 1) {
        const val = map.get(i);
        try std.testing.expectEqual(i * 2 + 100, val.?);
    }
    std.debug.print("  All updates verified!\n", .{});

    // Test 5: Insert new entries with getOrPutValue
    std.debug.print("Test 5: Inserting new entries with getOrPutValue...\n", .{});
    i = 1_000_000;
    while (i < 1_500_000) : (i += 1) {
        const entry = try map.getOrPutValue(alloc, i, i * 5);
        // Should be new, value should be i * 5
        try std.testing.expectEqual(i * 5, entry.value.*);
        if (i % 100_000 == 0) {
            std.debug.print("  Inserted {d} new entries\n", .{i - 1_000_000});
        }
    }
    std.debug.print("  Final size={d}, capacity={d}\n", .{ map.count(), map.capacity() });

    // Test 6: Heavy collision test
    std.debug.print("Test 6: Testing with collisions...\n", .{});
    var collision_map = HashMap(u32, u32, Context, 75){};
    defer collision_map.deinit(alloc);

    i = 0;
    while (i < 50_000) : (i += 1) {
        const key = (i << 8) | (i & 0xFF);
        try collision_map.put(alloc, key, i);
    }

    i = 0;
    while (i < 50_000) : (i += 1) {
        const key = (i << 8) | (i & 0xFF);
        const val = collision_map.get(key);
        try std.testing.expectEqual(i, val.?);
    }
    std.debug.print("  Collision test passed! size={d}, capacity={d}\n", .{ collision_map.count(), collision_map.capacity() });

    // Test 7: Random mixed operations with getOrPutValue
    std.debug.print("Test 7: Random mixed operations...\n", .{});
    var mixed_map = HashMap(u32, u32, Context, 75){};
    defer mixed_map.deinit(alloc);

    var prng = std.Random.DefaultPrng.init(42);
    const random = prng.random();

    i = 0;
    while (i < 100_000) : (i += 1) {
        const key = random.int(u32) % 50_000;

        if (random.boolean()) {
            // Use getOrPutValue to increment counter
            const entry = try mixed_map.getOrPutValue(alloc, key, 0);
            entry.value.* += 1;
        } else {
            // Direct put
            const val = random.int(u32);
            try mixed_map.put(alloc, key, val);
        }
    }
    std.debug.print("  Mixed operations test passed! size={d}\n", .{mixed_map.count()});

    std.debug.print("\n=== All Stress Tests Passed! ===\n", .{});
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
