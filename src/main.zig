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
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const arenaAlloc = arena.allocator();

    var bpe = try BPE.init(arenaAlloc, file);
    defer bpe.deinit(alloc, arenaAlloc);
    try bpe.populate(alloc);

    if (buildOptions.trace) {
        try bpe.printCount();
        try bpe.printText();
    }

    while (bpe.searchMaxPair()) |t| {
        const toSwap, const count = t;
        std.log.debug("Initiating proccess to replace {f} with {}", .{ toSwap, count });
        const newItem = bpe.reserveItem();
        try bpe.iterate(alloc, toSwap, newItem);
        if (try bpe.addPair(arenaAlloc, alloc, toSwap, newItem)) break;

        if (buildOptions.trace) {
            try bpe.printDic();
            try bpe.printCount();
            try bpe.printText();
        }

        if (buildOptions.debug) try bpe.verifyCount(alloc);
    }

    try bpe.printCount();
    try bpe.printText();
}

test {
    _ = @import("Trie.zig");
}

const Trie = @import("Trie.zig").Trie;
const BPE = @import("BPE.zig");

const std = @import("std");
const buildOptions = @import("buildOptions");

const Allocator = std.mem.Allocator;
const Order = std.math.Order;
const File = std.fs.File;
const Timer = std.time.Timer;
const io = std.io;
const math = std.math;
const assert = std.debug.assert;
