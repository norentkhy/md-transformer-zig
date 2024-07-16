const std = @import("std");
const assert = std.debug.assert;
const print = std.debug.print;
const expectEqual = std.testing.expectEqual;

pub fn FixedQueue(comptime T: type, size: usize) type {
    return struct {
        const Self = @This();
        queue: [size]?T = .{null} ** size,
        first_idx: usize = 0,
        last_idx: usize = 0,
        len: usize = 0,

        pub fn take(self: *Self) ?T {
            if (self.queue[self.first_idx]) |item| {
                self.queue[self.first_idx] = null;
                self.len -= 1;
                const take_idx_incremented = if (self.first_idx == size - 1) 0 else self.first_idx + 1;
                self.first_idx = take_idx_incremented;
                return item;
            }
            return null;
        }

        pub fn putFirst(self: *Self, item: T) void {
            const new_first_idx = if (self.first_idx == 0) size - 1 else self.first_idx - 1;
            if (self.queue[new_first_idx] != null) @panic("queue spot taken yo");
            self.queue[new_first_idx] = item;
            self.first_idx = new_first_idx;
            self.len += 1;
        }

        pub fn putLast(self: *Self, item: T) void {
            if (self.queue[self.last_idx] != null) @panic("queue spot taken yo");
            self.queue[self.last_idx] = item;
            self.last_idx = if (self.last_idx == size - 1) 0 else self.last_idx + 1;
            self.len += 1;
        }

        pub fn peek(self: Self, idx: usize) ?T {
            assert(idx < size);
            var actual_idx = self.first_idx + idx;
            if (actual_idx >= size) actual_idx -= size;
            return self.queue[actual_idx];
        }
    };
}

test "fill until full and flush all" {
    var q = FixedQueue(u8, 3){};
    q.putLast('a');
    q.putLast('b');
    q.putLast('c');
    try expectEqual('a', q.take());
    try expectEqual('b', q.take());
    try expectEqual('c', q.take());
}

test "circular putLast and take" {
    var q = FixedQueue(u8, 3){};
    try expectEqual(0, q.len);
    q.putLast('a');
    try expectEqual(1, q.len);
    q.putLast('b');
    try expectEqual(2, q.len);
    try expectEqual('a', q.take());
    try expectEqual(1, q.len);
    q.putLast('c');
    try expectEqual(2, q.len);
    try expectEqual('b', q.take());
    try expectEqual(1, q.len);
    q.putLast('d');
    try expectEqual(2, q.len);
    try expectEqual('c', q.take());
    try expectEqual(1, q.len);
    q.putLast('e');
    try expectEqual(2, q.len);
    try expectEqual('d', q.take());
    try expectEqual(1, q.len);
    q.putLast('f');
    try expectEqual(2, q.len);
    try expectEqual('e', q.take());
    try expectEqual(1, q.len);
    q.putLast('g');
    try expectEqual(2, q.len);
    try expectEqual('f', q.take());
    try expectEqual(1, q.len);
    try expectEqual('g', q.take());
    try expectEqual(0, q.len);
}

test "peeking" {
    var q = FixedQueue(u8, 4){};
    try expectEqual(null, q.peek(0));
    q.putLast('a');
    try expectEqual('a', q.peek(0));
    _ = q.take();
    try expectEqual(null, q.peek(0));
    q.putLast('b');
    try expectEqual('b', q.peek(0));
    q.putLast('c');
    try expectEqual('b', q.peek(0));
    try expectEqual('c', q.peek(1));
}
