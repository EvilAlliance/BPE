pub fn SortedArrayList(comptime T: type, comptime compare: if (@sizeOf(T) <= 8) *const fn (T, T) Order else *const fn (*const T, *const T) Order) type {
    const doNotUsePointer = @sizeOf(T) <= 8;
    return struct {
        const Self = @This();
        list: std.ArrayList(T) = .{},

        pub fn ensureTotalCapacity(self: *Self, alloc: Allocator, newCapacity: usize) !void {
            try self.list.ensureTotalCapacity(alloc, newCapacity);
        }

        pub fn putOrGet(self: *Self, alloc: Allocator, t: T) !?*T {
            return try self._append(alloc, t);
        }

        pub fn append(self: *Self, alloc: Allocator, t: T) !void {
            _ = try self._append(alloc, t) orelse return;
            @panic("This already exists");
        }

        fn _append(self: *Self, alloc: Allocator, t: T) !?*T {
            var order = compare(
                if (doNotUsePointer)
                    self.list.getLastOrNull() orelse {
                        try self.list.append(alloc, t);
                        return null;
                    }
                else
                    &(self.list.getLastOrNull() orelse {
                        try self.list.append(alloc, t);
                        return null;
                    }),
                if (doNotUsePointer) t else &t,
            );
            if (order == .eq) return &self.list.items[self.list.items.len - 1];

            if (order == .lt) {
                (try self.list.addOne(alloc)).* = t;
                return null;
            }

            const i = blk: {
                var l: usize = 0;
                var h: usize = self.list.items.len - 1;
                var mid: usize = undefined;
                while (l <= h) {
                    mid = l + ((h - l) / 2);

                    order = compare(
                        if (doNotUsePointer) self.list.items[mid] else &self.list.items[mid],
                        if (doNotUsePointer) t else &t,
                    );

                    switch (order) {
                        .lt => l = mid + 1,
                        .eq => return &self.list.items[mid],
                        .gt => {
                            if (mid == 0) break;
                            h = mid - 1;
                        },
                    }
                }

                break :blk l;
            };

            try self.list.insert(alloc, i, t);

            return null;
        }

        pub fn getConstPtr(self: *const Self, t: T) ?*const T {
            return self.getPtr(t);
        }

        pub fn getPtr(self: *const Self, t: T) ?*T {
            var l: usize = 0;
            var h: usize = self.list.items.len - 1;

            while (l <= h) {
                const mid = l + ((h - l) / 2);

                const order = compare(
                    if (doNotUsePointer) self.list.items[mid] else &self.list.items[mid],
                    if (doNotUsePointer) t else &t,
                );

                switch (order) {
                    .lt => l = mid + 1,
                    .eq => return &self.list.items[mid],
                    .gt => {
                        if (mid == 0) break;
                        h = mid - 1;
                    },
                }
            }

            return null;
        }

        pub fn get(self: *const Self, t: T) ?T {
            return (self.getPtr(t) orelse return null).*;
        }

        pub fn deinit(self: *Self, alloc: Allocator) void {
            self.list.deinit(alloc);
        }
    };
}

test "Pepe" {
    const alloc = std.testing.allocator;

    var list = SortedArrayList(usize, struct {
        pub fn get(a: usize, b: usize) Order {
            if (a < b) return .lt;
            if (a > b) return .gt;
            return .eq;
        }
    }.get){};
    defer list.deinit(alloc);

    try list.append(alloc, 7);
    std.debug.print("{any}\n", .{list.list.items});
    try list.append(alloc, 9);
    std.debug.print("{any}\n", .{list.list.items});
    try list.append(alloc, 6);

    std.debug.print("{any}\n", .{list.list.items});
    std.debug.print("{?}\n", .{list.getConstPtr(7)});
}

const std = @import("std");

const Order = std.math.Order;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
