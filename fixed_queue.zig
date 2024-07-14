const std = @import("std");
const assert = std.debug.assert;
const print = std.debug.print;
const expectEqual = std.testing.expectEqual;

pub fn FixedQueue(comptime T: type, size: usize) type {
    return struct {
        const Self = @This();
        queue: [size]?T = .{null} ** size,
        take_idx: usize = 0,
        put_idx: usize = 0,
        len: usize = 0,

        pub fn take(self: *Self) ?T {
            if (self.queue[self.take_idx]) |item| {
                self.queue[self.take_idx] = null;
                self.len -= 1;
                const take_idx_incremented = if (self.take_idx == size - 1) 0 else self.take_idx + 1;
                self.take_idx = take_idx_incremented;
                return item;
            }
            return null;
        }

        pub fn put(self: *Self, item: T) void {
            if (self.queue[self.put_idx] != null) @panic("queue spot taken yo");
            self.queue[self.put_idx] = item;
            self.len += 1;
            self.put_idx = if (self.put_idx == size - 1) 0 else self.put_idx + 1;
        }

        pub fn peek(self: Self, idx: usize) ?T {
            assert(idx < size);
            var actual_idx = self.take_idx + idx;
            if (actual_idx >= size) actual_idx -= size;
            return self.queue[actual_idx];
        }
    };
}

test "fill until full and flush all" {
    var q = FixedQueue(u8, 3){};
    q.put('a');
    q.put('b');
    q.put('c');
    try expectEqual('a', q.take());
    try expectEqual('b', q.take());
    try expectEqual('c', q.take());
}

test "circular put and take" {
    var q = FixedQueue(u8, 3){};
    try expectEqual(0, q.len);
    q.put('a');
    try expectEqual(1, q.len);
    q.put('b');
    try expectEqual(2, q.len);
    try expectEqual('a', q.take());
    try expectEqual(1, q.len);
    q.put('c');
    try expectEqual(2, q.len);
    try expectEqual('b', q.take());
    try expectEqual(1, q.len);
    q.put('d');
    try expectEqual(2, q.len);
    try expectEqual('c', q.take());
    try expectEqual(1, q.len);
    q.put('e');
    try expectEqual(2, q.len);
    try expectEqual('d', q.take());
    try expectEqual(1, q.len);
    q.put('f');
    try expectEqual(2, q.len);
    try expectEqual('e', q.take());
    try expectEqual(1, q.len);
    q.put('g');
    try expectEqual(2, q.len);
    try expectEqual('f', q.take());
    try expectEqual(1, q.len);
    try expectEqual('g', q.take());
    try expectEqual(0, q.len);
}

test "peeking" {
    var q = FixedQueue(u8, 4){};
    try expectEqual(null, q.peek(0));
    q.put('a');
    try expectEqual('a', q.peek(0));
    _ = q.take();
    try expectEqual(null, q.peek(0));
    q.put('b');
    try expectEqual('b', q.peek(0));
    q.put('c');
    try expectEqual('b', q.peek(0));
    try expectEqual('c', q.peek(1));
}
