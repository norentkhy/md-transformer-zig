const std = @import("std");

pub fn toNewOwner(
    comptime T: type,
    allocator: std.mem.Allocator,
    text_buffer: *std.ArrayList(T),
) !std.ArrayList(T) {
    const slice = try text_buffer.toOwnedSlice();
    return std.ArrayList(T).fromOwnedSlice(allocator, slice);
}

pub fn countItem(comptime T: type, slice: []const T, target_item: T) usize {
    var count: usize = 0;
    for (slice) |item| {
        if (item == target_item) count += 1;
    }
    return count;
}

pub fn hasItemAtLeast(comptime T: type, slice: []const T, target_item: T, minimum_count: usize) bool {
    var count: usize = 0;
    for (slice) |item| {
        if (item == target_item) count += 1;
        if (count == minimum_count) return true;
    }
    return false;
}
