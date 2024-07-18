const std = @import("std");
const print = std.debug.print;

test "bounded queue" {
    var q = BoundedQueue(u8, 3).new();
    try std.testing.expectEqual(q.len, 0);
    try q.put(.last, 'x');
    try std.testing.expectEqual(q.len, 1);
    try q.put(.last, 'y');
    try std.testing.expectEqual(q.len, 2);
    try q.put(.last, 'z');
    try std.testing.expectEqual(q.len, 3);
    try std.testing.expectEqual('x', q.take());
    try std.testing.expectEqual(q.len, 2);
    try std.testing.expectEqual('y', q.take());
    try std.testing.expectEqual(q.len, 1);
    try q.put(.last, 'a');
    try std.testing.expectEqual(q.len, 2);
    try std.testing.expectEqual('z', q.take());
    try std.testing.expectEqual(q.len, 1);
    try std.testing.expectEqual('a', q.take());
    try std.testing.expectEqual(q.len, 0);
}

pub fn BoundedQueue(T: type, capacity: usize) type {
    return struct {
        buffer: [capacity]?T = .{null} ** capacity,
        len: usize = 0,
        i_first: usize = 0,
        i_last: usize = 0,

        const Self = @This();
        const Position = enum { first, last };
        const Error = error{full};

        pub fn new() Self {
            return .{};
        }

        pub fn put(self: *Self, position: Position, item: T) !void {
            if (self.len == capacity) return Error.full;

            if (self.len == 0) {
                std.debug.assert(self.buffer[self.i_first] == null);
                std.debug.assert(self.buffer[self.i_last] == null);
                self.buffer[self.i_first] = item;
                self.len += 1;
                return;
            }

            switch (position) {
                .first => {
                    const i_first: usize = if (self.i_first == 0) capacity - 1 else self.i_first - 1;
                    std.debug.assert(self.buffer[i_first] == null);
                    self.buffer[i_first] = item;
                    self.i_first = i_first;
                    self.len += 1;
                },
                .last => {
                    const i_last: usize = if (self.i_last == capacity - 1) 0 else self.i_last + 1;
                    std.debug.assert(self.buffer[i_last] == null);
                    self.buffer[i_last] = item;
                    self.i_last = i_last;
                    self.len += 1;
                },
            }
        }

        pub fn take(self: *Self) ?T {
            if (self.len == 0) return null;
            const item = self.buffer[self.i_first];
            std.debug.assert(@TypeOf(item) == ?T);
            self.buffer[self.i_first] = null;
            if (self.len != 1) {
                self.i_first = if (self.i_first == capacity - 1) 0 else self.i_first + 1;
            }
            self.len -= 1;
            return item;
        }
    };
}
