// TODO: Consider updating this to radix trie
pub fn Trie(V: type) type {
    return union(enum) {
        const Self = @This();

        const GroupSize = 16;
        bridge: struct {
            child: [GroupSize]*Self = undefined,
            possiblePrefixes: u256 = 0,
            value: ?V,
        },
        split: struct {
            child: [GroupSize]*Self = undefined,
            possiblePrefixes: u256 = 0,
            value: ?V,
        },

        // Initialzation
        pub fn init(alloc: Allocator) !*Self {
            const self = try alloc.create(Self);
            self.* = .{ .split = .{ .value = null } };
            return self;
        }

        pub fn deinit(self: *Self, alloc: Allocator) void {
            var possiblePrefixes = switch (self.*) {
                .split => |s| s.possiblePrefixes,
                .bridge => |b| b.possiblePrefixes,
            };
            const childs = switch (self.*) {
                .split => |s| s.child,
                .bridge => |b| b.child,
            };

            var i: usize = 0;
            while (possiblePrefixes != 0) : (i += 1) {
                childs[i].deinit(alloc);
                possiblePrefixes &= possiblePrefixes - 1;
            }

            alloc.destroy(self);
        }

        // Utils

        inline fn countPrefixBefore(possiblePrefixes: u256, prefix: u8) u8 {
            const prefixesBefore = possiblePrefixes & (std.math.shl(u256, 1, prefix) - 1);
            return @intCast(@popCount(prefixesBefore));
        }

        inline fn countPrefixBeforeInclusive(possiblePrefixes: u256, prefix: u8) usize {
            const prefixesBefore = possiblePrefixes & @as(u256, @intCast(std.math.shl(u257, 1, prefix + 1) - 1));
            return @intCast(@popCount(prefixesBefore));
        }

        inline fn lastPrefix(possiblePrefixes: u256) u8 {
            const countAfter = @clz(possiblePrefixes);
            assert(countAfter <= std.math.maxInt(u8));

            return std.math.maxInt(u8) - @as(u8, @intCast(countAfter));
        }

        inline fn firstPrefix(possiblePrefixes: u256) u8 {
            const countAfter = @ctz(possiblePrefixes);
            assert(countAfter <= std.math.maxInt(u8));

            return @intCast(countAfter);
        }

        inline fn getPrefix(_possiblePrefixes: u256, count: u8) u8 {
            var possiblePrefixes = _possiblePrefixes;
            for (0..count) |_|
                possiblePrefixes &= possiblePrefixes - 1;

            return firstPrefix(possiblePrefixes);
        }

        inline fn hasPrefix(possiblePrefixes: u256, prefix: u8) bool {
            return (possiblePrefixes & std.math.shl(u256, 1, prefix)) != 0;
        }

        inline fn removePrefix(possiblePrefixes: *u256, prefix: u8) void {
            possiblePrefixes.* = possiblePrefixes.* & ~std.math.shl(u256, 1, prefix);
        }

        inline fn addPrefix(possiblePrefixes: *u256, prefix: u8) void {
            possiblePrefixes.* = possiblePrefixes.* | std.math.shl(u256, 1, prefix);
        }

        inline fn shiftChilds(childs: []*Self, shift: usize, child: *Self) void {
            var i: usize = childs.len - 1;
            while (i > shift) {
                childs[i] = childs[i - 1];
                i -= 1;
            }

            childs[shift] = child;
        }

        // Private Functions

        // NOTE: Returns itself
        fn transformPrefixBridge(self: *Self, alloc: Allocator) Allocator.Error!*Self {
            assert(std.meta.activeTag(self.*) == .split and @popCount(self.split.possiblePrefixes) == GroupSize);
            const child1: *Self = try .init(alloc);
            const child2: *Self = try .init(alloc);

            var index1: u8 = 0;
            var index2: u8 = 0;

            var possiblePrefixes = self.split.possiblePrefixes;
            var i: usize = 0;
            while (possiblePrefixes != 0) : (i += 1) {
                const prefix: u8 = firstPrefix(possiblePrefixes);
                const child = if (prefix <= comptime std.math.maxInt(u8) >> 1) child1 else child2;
                const index = if (prefix <= comptime std.math.maxInt(u8) >> 1) &index1 else &index2;

                addPrefix(&child.split.possiblePrefixes, prefix);

                child.split.child[index.*] = self.split.child[i];
                index.* += 1;

                possiblePrefixes &= possiblePrefixes - 1;
            }

            const value = self.split.value;
            self.* = .{ .bridge = .{ .value = value } };
            addPrefix(&self.bridge.possiblePrefixes, comptime std.math.maxInt(u8) >> 1);
            addPrefix(&self.bridge.possiblePrefixes, std.math.maxInt(u8));

            self.bridge.child[0] = child1;
            self.bridge.child[1] = child2;

            return self;
        }

        // NOTE: Returns itself
        fn divideBridge(self: *Self, alloc: Allocator, splitIndex: u8) Allocator.Error!*Self {
            assert(std.meta.activeTag(self.*) == .bridge and @popCount(self.bridge.child[splitIndex].split.possiblePrefixes) == GroupSize);
            const b = &self.bridge;

            const child1: *Self = b.child[splitIndex];
            const child2: *Self = try .init(alloc);

            const dividePrefixes = child1.split.possiblePrefixes;
            const divideChilds = child1.split.child;
            child1.* = .{ .split = .{ .value = null } };

            const min = if (splitIndex == 0) 0 else getPrefix(b.possiblePrefixes, splitIndex - 1);
            const max = getPrefix(b.possiblePrefixes, splitIndex);
            const mid = min + ((max - min) >> 1);
            assert(min < mid and mid < max);

            var index1: u8 = 0;
            var index2: u8 = 0;

            var possiblePrefixes = dividePrefixes;
            var i: usize = 0;
            while (possiblePrefixes != 0) : (i += 1) {
                defer possiblePrefixes &= possiblePrefixes - 1;

                const prefix: u8 = firstPrefix(possiblePrefixes);

                const child = if (prefix <= mid) child1 else child2;
                const index = if (prefix <= mid) &index1 else &index2;

                addPrefix(&child.split.possiblePrefixes, prefix);
                child.split.child[index.*] = divideChilds[i];
                index.* += 1;
            }

            addPrefix(&b.possiblePrefixes, mid);
            shiftChilds(b.child[0..@popCount(b.possiblePrefixes)], splitIndex + 1, child2);

            return self;
        }

        // API
        pub fn insertChar(self: *Self, alloc: Allocator, prefix: u8) Allocator.Error!*Self {
            switch (self.*) {
                .bridge => |*b| {
                    const splitBelong = countPrefixBefore(b.possiblePrefixes, prefix);

                    const child = b.child[splitBelong];

                    if (@popCount(child.split.possiblePrefixes) == GroupSize) return try (try self.divideBridge(alloc, splitBelong)).insertChar(alloc, prefix);

                    return try child.insertChar(alloc, prefix);
                },
                .split => |*s| {
                    if (@popCount(s.possiblePrefixes) == GroupSize) return try (try self.transformPrefixBridge(alloc)).insertChar(alloc, prefix);

                    if (hasPrefix(s.possiblePrefixes, prefix)) return s.child[countPrefixBefore(s.possiblePrefixes, prefix)];
                    addPrefix(&s.possiblePrefixes, prefix);
                    const child: *Self = try .init(alloc);

                    shiftChilds(s.child[0..@popCount(s.possiblePrefixes)], countPrefixBefore(s.possiblePrefixes, prefix), child);

                    return child;
                },
            }
        }

        pub fn getChar(self: *Self, prefix: u8) ?*Self {
            switch (self.*) {
                .bridge => |*b| {
                    const splitBelong = countPrefixBefore(b.possiblePrefixes, prefix);

                    const child = b.child[splitBelong];

                    return child.getChar(prefix);
                },
                .split => |*s| {
                    if (hasPrefix(s.possiblePrefixes, prefix)) return s.child[countPrefixBefore(s.possiblePrefixes, prefix)];

                    return null;
                },
            }
        }

        pub fn prettyPrint(self: *Self, w: *std.io.Writer) !void {
            try self.prettyPrintIndent(w, 0);
        }

        fn prettyPrintIndent(self: *Self, w: *std.io.Writer, indent: usize) !void {
            const spaces = "  " ** 20;
            const indentStr = spaces[0..@min(indent * 2, spaces.len)];

            switch (self.*) {
                .bridge => |b| {
                    try w.print("{s}Bridge (value: {?x})\n", .{ indentStr, b.value });

                    var possiblePrefixes = b.possiblePrefixes;
                    var i: usize = 0;
                    while (possiblePrefixes != 0) : (i += 1) {
                        const prefix = firstPrefix(possiblePrefixes);
                        try w.print("{s}  [{x:0>2}] ->\n", .{ indentStr, prefix });
                        try b.child[i].prettyPrintIndent(w, indent + 2);
                        possiblePrefixes &= possiblePrefixes - 1;
                    }
                },
                .split => |s| {
                    try w.print("{s}Split (value: {?x})\n", .{ indentStr, s.value });

                    var possiblePrefixes = s.possiblePrefixes;
                    var i: usize = 0;
                    while (possiblePrefixes != 0) : (i += 1) {
                        const prefix = firstPrefix(possiblePrefixes);
                        if (prefix >= 32 and prefix <= 126) {
                            try w.print("{s}  ['{c}'] ->\n", .{ indentStr, prefix });
                        } else {
                            try w.print("{s}  [{x:0>2}] ->\n", .{ indentStr, prefix });
                        }
                        try s.child[i].prettyPrintIndent(w, indent + 2);
                        possiblePrefixes &= possiblePrefixes - 1;
                    }
                },
            }
        }

        pub fn setVaue(self: *Self, value: V) void {
            const val = switch (self.*) {
                .split => |*s| &s.value,
                .bridge => |*b| &b.value,
            };

            val.* = value;
        }

        pub fn getValue(self: *Self) ?V {
            return switch (self.*) {
                .split => |s| s.value,
                .bridge => |b| b.value,
            };
        }
    };
}

test "Adding individual chars ensuring ordered" {
    const Node = Trie(u16);
    const alloc = std.testing.allocator;

    const root: *Node = try .init(alloc);
    defer root.deinit(alloc);

    const B = try root.insertChar(alloc, 'b');

    try std.testing.expect(Node.hasPrefix(root.split.possiblePrefixes, 'b'));
    try std.testing.expect(root.split.child[0] == B);

    const A = try root.insertChar(alloc, 'a');

    try std.testing.expect(Node.hasPrefix(root.split.possiblePrefixes, 'a'));
    try std.testing.expect(root.split.child[0] == A);
    try std.testing.expect(root.split.child[1] == B);
}

test "Adding individual, going beyond the miximus" {
    const Node = Trie(u16);
    const alloc = std.testing.allocator;

    const root: *Node = try .init(alloc);
    defer root.deinit(alloc);
    for (0..std.math.maxInt(u8)) |i| {
        _ = try root.insertChar(alloc, @intCast(i));
    }

    try std.testing.expect(std.meta.activeTag(root.*) == .bridge);
}

const std = @import("std");

const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
