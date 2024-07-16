const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;
const MdToken = @import("./md_streaming.zig").Token;
const MdTokenStream = @import("./md_streaming.zig").TokenStream;
const FixedQueue = @import("./fixed_queue.zig").FixedQueue;
const countItem = @import("./utils.zig").countItem;
const hasItemAtLeast = @import("./utils.zig").hasItemAtLeast;
const toNewOwner = @import("./utils.zig").toNewOwner;

const HtmlFromMdStream = struct {
    const Self = @This();
    const HtmlQueue = FixedQueue(HtmlToken, 10);
    const MdQueue = FixedQueue(MdToken, 3);

    md_token_stream: *MdTokenStream,
    context_stack: std.ArrayList(Context),
    html_queue: HtmlQueue = HtmlQueue{},
    md_queue: MdQueue = MdQueue{},
    scratch_allocator: std.mem.Allocator,

    pub fn init(md_token_stream: *MdTokenStream, scratch_allocator: std.mem.Allocator) !Self {
        return .{
            .scratch_allocator = scratch_allocator,
            .md_token_stream = md_token_stream,
            .context_stack = std.ArrayList(Context).init(scratch_allocator),
        };
    }

    pub fn deinit(self: Self) void {
        self.context_stack.deinit();
    }

    /// ideally want to reset scratch-allocations at the start of this
    pub fn next(self: *Self, content_allocator: std.mem.Allocator) !?HtmlToken {
        if (self.html_queue.take()) |html_token| return html_token;

        if (self.peekMdToken(0)) |md_token| {
            const context = self.context_stack.getLastOrNull() orelse Context.from(md_token);
            if (self.context_stack.items.len == 0) {
                try self.context_stack.append(context);
                return context.startTag();
            }

            switch (context) {
                .paragraph => {
                    try self.parseParagraph(content_allocator);
                },
                .header1 => {
                    _ = self.md_queue.take();
                    try self.parseHeader(content_allocator);
                },
            }
            return self.html_queue.take();
        }

        return null;
    }

    fn peekMdToken(self: *Self, idx: usize) ?MdToken {
        while (self.md_queue.len <= idx) {
            const md_token = self.md_token_stream.next() orelse return null;
            self.md_queue.putLast(md_token);
        }
        return self.md_queue.peek(idx);
    }

    fn nextMdToken(self: *Self) ?MdToken {
        return self.md_queue.take() orelse self.md_token_stream.next();
    }

    fn headerAfterParagraphPeeked(self: *Self) bool {
        const peek0 = self.peekMdToken(0) orelse return false;
        const is_header_symbol = Context.from(peek0) == .header1;
        const peek1 = self.peekMdToken(1) orelse return is_header_symbol;
        return is_header_symbol and peek1 == .space;
    }

    fn parseParagraph(self: *Self, content_allocator: std.mem.Allocator) !void {
        var text_buffer = std.ArrayList(u8).init(content_allocator);
        defer text_buffer.deinit();

        parsing: while (self.peekMdToken(0)) |md_token| {
            switch (md_token) {
                .alphanumerical => |content| {
                    _ = self.nextMdToken();
                    try text_buffer.appendSlice(content);
                },

                .symbol => {
                    var nested_sequence = std.ArrayList(HtmlToken).init(self.scratch_allocator);
                    defer nested_sequence.deinit();
                    var text_before = std.ArrayList(HtmlToken).init(self.scratch_allocator);
                    defer text_before.deinit();

                    try self.parseNested(content_allocator, &text_before, &nested_sequence);

                    if (text_before) |text| try text_buffer.appendSlice(text);
                    for (nested_sequence.items) |html_token| self.html_queue.putLast(html_token);
                },

                .space => |content| {
                    _ = self.nextMdToken();
                    if (self.headerAfterParagraphPeeked()) break :parsing;
                    if (self.peekMdToken(0) == null) break :parsing;
                    const new_line_count = countItem(u8, content, '\n');
                    if (new_line_count > 1) break :parsing;

                    if (new_line_count == 1) {
                        self.html_queue.putLast(HtmlToken.line_break);
                        break :parsing;
                    }

                    try text_buffer.append(' ');
                    continue :parsing;
                },
            }
        }

        self.html_queue.putFirst(.{ .text_node = try toNewOwner(u8, content_allocator, &text_buffer) });
        const context = self.context_stack.pop();
        self.html_queue.putLast(context.endTag());
    }

    fn parseHeader(self: *Self, allocator: std.mem.Allocator) !void {
        var text_buffer = std.ArrayList(u8).init(allocator);
        defer text_buffer.deinit();

        parsing: while (self.nextMdToken()) |md_token| {
            switch (md_token) {
                .alphanumerical => |content| try text_buffer.appendSlice(content),
                .symbol => |content| try text_buffer.appendSlice(content),
                .space => |content| {
                    if (hasItemAtLeast(u8, content, '\n', 1)) break :parsing;
                    if (self.peekMdToken(0) == null) break :parsing;
                    if (text_buffer.items.len > 0) try text_buffer.append(' ');
                },
            }
        }

        self.html_queue.putLast(.{ .text_node = try toNewOwner(u8, allocator, &text_buffer) });
        const context = self.context_stack.pop();
        self.html_queue.putLast(context.endTag());
    }

    /// meant to be used only by other parse methods
    fn parseNested(
        self: *Self,
        content_allocator: std.mem.Allocator,
        text_before: *std.ArrayList(u8),
        sequence: *std.ArrayList(HtmlToken),
    ) !?[]const u8 {
        _ = content_allocator;

        while (self.nextMdToken()) |md_token| {
            switch (md_token) {
                .alphanumerical => {},
                .space => {
                    if (text_before.len > 0) try sequence.append(' ');
                },
                .symbol => {},
            }
        }
        return text_before;
        // while (self.nextMdToken()) |md_token| {
        //     switch (md_token) {
        //         .alphanumerical => {
        //         },
        //         .symbol => {
        //         },
        //         .space => {
        //         },
        //     }
        // }
    }
};

const Context = union(ContextTag) {
    const Self = @This();
    const paragraph = HtmlTagPair{ .start_tag = .paragraph_start, .end_tag = .paragraph_end };
    const header1 = HtmlTagPair{ .start_tag = .header1_start, .end_tag = .header1_end };

    paragraph: HtmlTagPair,
    header1: HtmlTagPair,

    pub fn from(md_token: MdToken) Self {
        switch (md_token) {
            .alphanumerical => return Self{ .paragraph = paragraph },
            .symbol => |content| {
                switch (countItem(u8, content, '#')) {
                    1 => return Self{ .header1 = header1 },
                    else => {},
                }
                return Self{ .paragraph = paragraph };
            },
            else => unreachable,
        }
        unreachable;
    }

    pub fn startTag(self: Self) HtmlToken {
        return switch (self) {
            inline else => |context| context.start_tag,
        };
    }

    pub fn endTag(self: Self) HtmlToken {
        return switch (self) {
            inline else => |context| context.end_tag,
        };
    }
};

const ContextTag = enum { paragraph, header1 };

const HtmlTagPair = struct { start_tag: HtmlToken, end_tag: HtmlToken };

const HtmlToken = union(HtmlTag) {
    line_break,
    paragraph_start,
    paragraph_end,
    header1_start,
    header1_end,
    text_node: std.ArrayList(u8),

    pub fn deinit(self: HtmlToken) void {
        return switch (self) {
            .text_node => |arrayList| arrayList.deinit(),
            else => {},
        };
    }

    pub fn serialize(self: HtmlToken) []const u8 {
        return switch (self) {
            .line_break => "<br>",
            .paragraph_start => "<p>",
            .paragraph_end => "</p>",
            .header1_start => "<h1>",
            .header1_end => "</h1>",
            .text_node => |text_buffer| text_buffer.items,
        };
    }
};

const HtmlTag = enum {
    line_break,
    paragraph_start,
    paragraph_end,
    header1_start,
    header1_end,
    text_node,
};

test "test two next calls for one paragraph" {
    print("\n\n", .{});
    var tokens = [_]MdToken{
        MdToken{ .alphanumerical = "hello" },
        MdToken{ .space = " " },
        MdToken{ .alphanumerical = "moto" },
        MdToken{ .space = "\n" },
        MdToken{ .symbol = "#" },
        MdToken{ .space = " " },
        MdToken{ .alphanumerical = "moto" },
        MdToken{ .space = " " },
        MdToken{ .alphanumerical = "moto" },
        MdToken{ .space = "\n" },
        MdToken{ .alphanumerical = "moo" },
        MdToken{ .space = " " },
        MdToken{ .alphanumerical = "desu" },
        MdToken{ .space = " " },
        MdToken{ .alphanumerical = "desu" },
        MdToken{ .space = " " },
        MdToken{ .symbol = "**`" },
        // MdToken{ .alphanumerical = "kawaiii" },
        // MdToken{ .symbol = "`**_" },
        // MdToken{ .space = "\n\n" },
        // MdToken{ .alphanumerical = "issa" },
        // MdToken{ .space = " " },
        // MdToken{ .alphanumerical = "new" },
        // MdToken{ .space = " " },
        // MdToken{ .alphanumerical = "paragraph" },
        // MdToken{ .space = "\n" },
        // MdToken{ .alphanumerical = "gotta" },
        // MdToken{ .space = " " },
        // MdToken{ .alphanumerical = "tell" },
        // MdToken{ .space = " " },
        // MdToken{ .alphanumerical = "you" },
        // MdToken{ .space = " " },
        // MdToken{ .alphanumerical = "about" },
        // MdToken{ .space = " " },
        // MdToken{ .alphanumerical = "shell" },
        // MdToken{ .symbol = "-" },
        // MdToken{ .alphanumerical = "scripts" },
        // MdToken{ .space = " " },
        // MdToken{ .alphanumerical = "man" },
        // MdToken{ .space = "\n" },
        // MdToken{ .symbol = "```" },
        // MdToken{ .alphanumerical = "sh" },
        // MdToken{ .space = "\n" },
        // MdToken{ .alphanumerical = "echo" },
        // MdToken{ .space = " " },
        // MdToken{ .alphanumerical = "hello" },
        // MdToken{ .space = " " },
        // MdToken{ .alphanumerical = "world" },
        // MdToken{ .symbol = ";" },
        // MdToken{ .space = "\n" },
        // MdToken{ .symbol = "```" },
    };
    var md_token_stream = MdTokenStream.fromTokens(&tokens);
    var parser = try HtmlFromMdStream.init(&md_token_stream, std.testing.allocator);
    defer parser.deinit();

    while (try parser.next(std.testing.allocator)) |token| {
        defer token.deinit();
        print("{s}\n", .{token.serialize()});
    }
}
