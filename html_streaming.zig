const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;
const MdToken = @import("./md_streaming.zig").Token;
const MdTokenStream = @import("./md_streaming.zig").TokenStream;
const FixedQueue = @import("./fixed_queue.zig").FixedQueue;

const HtmlFromMdStream = struct {
    const Self = @This();
    const HtmlQueue = FixedQueue(HtmlToken, 3);
    const MdQueue = FixedQueue(MdToken, 3);

    md_token_stream: *MdTokenStream,
    context_stack: std.ArrayList(Context),
    html_queue: HtmlQueue = HtmlQueue{},
    md_queue: MdQueue = MdQueue{},

    pub fn init(md_token_stream: *MdTokenStream, allocator: std.mem.Allocator) !Self {
        return .{
            .md_token_stream = md_token_stream,
            .context_stack = std.ArrayList(Context).init(allocator),
        };
    }

    pub fn deinit(self: Self) void {
        self.context_stack.deinit();
    }

    pub fn next(self: *Self, allocator: std.mem.Allocator) !?HtmlToken {
        if (self.html_queue.take()) |html_token| return html_token;

        if (self.peekMdToken(0)) |md_token| {
            const context = self.context_stack.getLastOrNull() orelse Context.from(md_token);
            if (self.context_stack.items.len == 0) {
                try self.context_stack.append(context);
                return context.startTag();
            }

            var text_buffer = std.ArrayList(u8).init(allocator);
            defer text_buffer.deinit();

            switch (context) {
                .paragraph => {
                    try self.parseParagraph(&text_buffer);
                },
                .header1 => {
                    _ = self.md_queue.take();
                    try self.parseHeader(&text_buffer);
                },
            }

            if (text_buffer.items.len == 0) return self.html_queue.take();
            print("text: {s}\n", .{text_buffer.items});
            return HtmlToken{ .text_node = try toNewOwner(allocator, &text_buffer) };
        }

        return null;
    }

    fn peekMdToken(self: *Self, idx: usize) ?MdToken {
        while (self.md_queue.len <= idx) {
            const md_token = self.md_token_stream.next() orelse return null;
            self.md_queue.put(md_token);
        }
        return self.md_queue.peek(idx);
    }

    fn nextMdToken(self: *Self) ?MdToken {
        return self.md_queue.take() orelse self.md_token_stream.next();
    }

    fn parseParagraph(self: *Self, text_buffer: *std.ArrayList(u8)) !void {
        ingestion: while (self.nextMdToken()) |md_token| {
            switch (md_token) {
                .space => |content| {
                    var new_line_count: usize = 0;
                    for (content) |char| {
                        if (char == '\n') new_line_count += 1;
                    }

                    const md_token_peek0 = self.peekMdToken(0);
                    const md_token_peek1 = self.peekMdToken(1);
                    const header_peeked = header_peeked: {
                        const peek0 = md_token_peek0 orelse break :header_peeked false;
                        const is_header_symbol = Context.from(peek0) == .header1;
                        const peek1 = md_token_peek1 orelse break :header_peeked is_header_symbol;
                        break :header_peeked is_header_symbol and peek1 == .space;
                    };
                    if (header_peeked) break :ingestion;
                    if (self.peekMdToken(0) == null) break :ingestion;
                    if (new_line_count > 1) break :ingestion;

                    if (new_line_count == 1) {
                        self.html_queue.put(HtmlToken.line_break);
                        return;
                    }

                    try text_buffer.append(' ');
                    continue :ingestion;
                },

                .symbol => @panic("time to handle symbols in paragraphs"),

                .alphanumerical => |content| {
                    for (content) |char| try text_buffer.append(char);
                },
            }
        }

        const context = self.context_stack.pop();
        self.html_queue.put(context.endTag());
    }

    fn parseHeader(self: *Self, text_buffer: *std.ArrayList(u8)) !void {
        ingestion: while (self.nextMdToken()) |md_token| {
            switch (md_token) {
                .alphanumerical => |content| try text_buffer.appendSlice(content),
                .symbol => |content| try text_buffer.appendSlice(content),
                .space => |content| {
                    for (content) |char| {
                        if (char == '\n') break :ingestion;
                    }

                    try text_buffer.append(' ');
                    continue :ingestion;
                },
            }
        }

        const context = self.context_stack.pop();
        self.html_queue.put(context.endTag());
    }
};

const Context = union(ContextTag) {
    const Self = @This();
    paragraph: HtmlTagPair,
    header1: HtmlTagPair,

    pub fn from(md_token: MdToken) Self {
        switch (md_token) {
            .alphanumerical => return Self{ .paragraph = HtmlTagPair{
                .start_tag = HtmlToken.paragraph_start,
                .end_tag = HtmlToken.paragraph_end,
            } },
            .symbol => |content| {
                var headerCount: u8 = 0;
                for (content) |char| {
                    if (char == '#') headerCount += 1;
                }
                if (headerCount == 1) return Self{ .header1 = HtmlTagPair{
                    .start_tag = HtmlToken.header1_start,
                    .end_tag = HtmlToken.header1_end,
                } };
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

fn toNewOwner(allocator: std.mem.Allocator, text_buffer: *std.ArrayList(u8)) !std.ArrayList(u8) {
    const slice = try text_buffer.toOwnedSlice();
    return std.ArrayList(u8).fromOwnedSlice(allocator, slice);
}

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
        // MdToken{ .space = " " },
        // MdToken{ .alphanumerical = "moto" },
        // MdToken{ .space = " " },
        // MdToken{ .alphanumerical = "moto" },
        // MdToken{ .space = "\n" },
        // MdToken{ .alphanumerical = "moo" },
        // MdToken{ .space = " " },
        // MdToken{ .alphanumerical = "desu" },
        // MdToken{ .space = " " },
        // MdToken{ .alphanumerical = "desu" },
        // MdToken{ .space = " " },
        // MdToken{ .symbol = "**`" },
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
        print("parsed: {any}\n\n", .{token});
    }
}
