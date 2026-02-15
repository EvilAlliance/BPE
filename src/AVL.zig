pub const Node = struct {
    const Self = @This();
    left: ?*Node = null,
    right: ?*Node = null,
    height: isize = 0,

    pub fn updateHeight(self: *Self) isize {
        const max = @max(if (self.left) |l| l.height else 0, if (self.right) |r| r.height else 0);
        self.height = 1 + max;
        return self.height;
    }

    pub fn getBalance(self: *const Self) isize {
        const l = if (self.left) |l| l.height else 0;
        const r = if (self.right) |r| r.height else 0;

        return r - l;
    }

    pub fn balance(self: **Self) void {
        const b = self.*.getBalance();

        if (b == 2)
            if (self.*.right.?.getBalance() >= 0)
                rotateLeft(self)
            else
                rotateRightLeft(self)
        else if (b == -2)
            if (self.*.left.?.getBalance() <= 0)
                rotateRight(self)
            else
                rotateLeftRight(self);
    }

    fn rotateLeft(self: **Self) void {
        const a = self.*;
        const b = a.right.?;

        const II = b.left;

        b.left = a;
        a.right = II;

        _ = a.updateHeight();

        self.* = b;
    }

    fn rotateRight(self: **Self) void {
        const a = self.*;
        const b = a.left.?;

        const II = b.right;

        b.right = a;
        a.left = II;

        _ = a.updateHeight();

        self.* = b;
    }

    fn rotateRightLeft(self: **Self) void {
        const a = self.*;
        const b = a.right.?;
        const c = b.left.?;

        const II = c.left;
        const III = c.right;

        b.left = III;
        c.right = b;
        a.right = II;
        c.left = a;

        _ = a.updateHeight();
        _ = b.updateHeight();
        _ = c.updateHeight();

        self.* = c;
    }

    fn rotateLeftRight(self: **Self) void {
        const a = self.*;
        const b = a.left.?;
        const c = b.right.?;

        const II = c.right;
        const III = c.left;

        b.right = III;
        c.left = b;
        a.left = II;
        c.right = a;

        _ = a.updateHeight();
        _ = b.updateHeight();
        _ = c.updateHeight();

        self.* = c;
    }
};

pub fn AVL(comptime comepareFn: *const fn (*const Node, *const Node) Order) type {
    return struct {
        const Self = @This();
        root: ?*Node = null,
        count: usize = 0,

        fn compare(l: *const Node, r: *const Node) Order {
            return comepareFn(l, r);
        }

        pub fn putOrGet(self: *Self, node: *Node) ?*Node {
            const existing = _put(&self.root, node);
            if (existing == null) self.count += 1;
            return existing;
        }

        pub fn put(self: *Self, node: *Node) error{RepeatedNode}!void {
            self.count += 1;
            if (_put(&self.root, node)) |_| return error.RepeatedNode;
        }

        fn _put(root: *?*Node, toPut: *Node) ?*Node {
            if (root.* == null) {
                _ = toPut.updateHeight();
                root.* = toPut;
                return null;
            }
            const order = compare(root.*.?, toPut);
            if (order == .eq) return root.*;

            const result = _put(&if (order == .gt) root.*.?.left else root.*.?.right, toPut);

            _ = root.*.?.updateHeight();

            Node.balance(&root.*.?);

            return result;
        }

        pub fn get(self: *Self, node: *const Node) ?*Node {
            var current = self.root;

            while (current) |x| {
                const order = compare(x, node);
                if (order == .eq) return x;
                current = if (order == .gt) x.left else x.right;
            }

            return null;
        }

        pub fn getConst(self: *const Self, node: *Node) ?*const Node {
            return self.get(node);
        }

        pub fn delete(self: *Self, node: *Node) ?*Node {
            const r = _delete(&self.root, node);
            if (r) |_| self.count -= 1;

            return r;
        }

        fn _delete(root: *?*Node, toDelete: *Node) ?*Node {
            if (root.* == null) return null;

            const order = compare(root.*.?, toDelete);
            const ret = if (order == .eq) blk: {
                const ret = root.*;

                if (root.*.?.left) |*l| {
                    if (root.*.?.right) |r| {
                        var current: *Node = l.*;
                        while (current.right) |newLR| current = newLR;

                        const predecessor = _delete(&root.*.?.left, current).?;
                        predecessor.left = l.*;
                        predecessor.right = r;
                        root.* = predecessor;
                    }
                } else {
                    root.* = root.*.?.left orelse root.*.?.right;
                }

                break :blk ret;
            } else _delete(&if (order == .gt) root.*.?.left else root.*.?.right, toDelete);

            if (root.*) |*r| {
                _ = r.*.updateHeight();
                Node.balance(r);
            }

            return ret;
        }

        pub fn prettyPrint(self: *const Self, alloc: Allocator, comptime getValueFn: *const fn (Allocator, *const Node) []const u8) !void {
            const stdout = std.fs.File.stdout();
            var buf: [8192]u8 = undefined;
            var writer = stdout.writer(&buf);
            var w = &writer.interface;
            defer _ = w.flush() catch false;

            try w.print("\n=== AVL Tree (count: {}) ===\n", .{self.count});
            if (self.root) |root| {
                try printNode(w, alloc, root, "", true, getValueFn);
            } else {
                try w.print("(empty)\n", .{});
            }
            try w.print("========================\n\n", .{});
        }

        fn printNode(w: *std.io.Writer, alloc: Allocator, node: *const Node, prefix: []const u8, isLast: bool, comptime getValueFn: *const fn (Allocator, *const Node) []const u8) !void {
            const connector = if (isLast) "└── " else "├── ";
            const value = getValueFn(alloc, node);

            try w.print("{s}{s}{s} (height: {}, balance: {})\n", .{ prefix, connector, value, node.height, node.getBalance() });

            const childPrefix = if (isLast) "    " else "│   ";
            const newPrefix = try std.fmt.allocPrint(alloc, "{s}{s}", .{ prefix, childPrefix });

            // Always print left child
            if (node.left) |left| {
                try printNode(w, alloc, left, newPrefix, false, getValueFn);
            } else {
                try w.print("{s}├── null\n", .{newPrefix});
            }

            // Always print right child
            if (node.right) |right| {
                try printNode(w, alloc, right, newPrefix, true, getValueFn);
            } else {
                try w.print("{s}└── null\n", .{newPrefix});
            }
        }
    };
}

test "AVL tree delete operations" {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    const allocGeneral = gpa.allocator();
    defer _ = gpa.deinit();

    var arena: std.heap.ArenaAllocator = .init(allocGeneral);
    const alloc = arena.allocator();
    defer arena.deinit();

    const Item = struct {
        const Self = @This();
        key: usize,
        value: usize,
        node: Node = .{},

        pub fn compareNode(lNode: *const Node, rNode: *const Node) Order {
            const l: *const Self = @fieldParentPtr("node", lNode);
            const r: *const Self = @fieldParentPtr("node", rNode);

            if (l.key > r.key) return .gt;
            if (l.key == r.key) return .eq;
            if (l.key < r.key) return .lt;

            unreachable;
        }
        pub fn get(a: Allocator, node: *const Node) []const u8 {
            const item: *const Self = @fieldParentPtr("node", node);
            return std.fmt.allocPrint(a, "k:{} v:{}", .{ item.key, item.value }) catch unreachable;
        }
    };

    var item1 = Item{ .key = 5, .value = 100 };
    var item2 = Item{ .key = 3, .value = 200 };
    var item3 = Item{ .key = 7, .value = 300 };
    var item4 = Item{ .key = 2, .value = 400 };
    var item5 = Item{ .key = 4, .value = 500 };
    var item6 = Item{ .key = 6, .value = 600 };
    var item7 = Item{ .key = 8, .value = 700 };

    var avl = AVL(Item.compareNode){};

    // Insert nodes
    std.debug.print("\n=== Inserting nodes ===\n", .{});
    try avl.put(&item1.node);
    try avl.put(&item2.node);
    try avl.put(&item3.node);
    try avl.put(&item4.node);
    try avl.put(&item5.node);
    try avl.put(&item6.node);
    try avl.put(&item7.node);

    try std.testing.expectEqual(@as(usize, 7), avl.count);
    std.debug.print("After insertion:\n", .{});
    try avl.prettyPrint(alloc, Item.get);

    // Delete a leaf node
    std.debug.print("\n=== Deleting leaf node (key=2) ===\n", .{});
    _ = avl.delete(&item4.node);
    try std.testing.expectEqual(@as(usize, 6), avl.count);
    try avl.prettyPrint(alloc, Item.get);

    // Delete a node with one child
    std.debug.print("\n=== Deleting node with one child (key=8) ===\n", .{});
    _ = avl.delete(&item7.node);
    try std.testing.expectEqual(@as(usize, 5), avl.count);
    try avl.prettyPrint(alloc, Item.get);

    // Delete a node with two children
    std.debug.print("\n=== Deleting node with two children (key=3) ===\n", .{});
    _ = avl.delete(&item2.node);
    try std.testing.expectEqual(@as(usize, 4), avl.count);
    try avl.prettyPrint(alloc, Item.get);

    // Delete another node with two children (root)
    std.debug.print("\n=== Deleting root node with two children (key=5) ===\n", .{});
    _ = avl.delete(&item1.node);
    try std.testing.expectEqual(@as(usize, 3), avl.count);
    try avl.prettyPrint(alloc, Item.get);
}

const std = @import("std");

const Order = std.math.Order;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
