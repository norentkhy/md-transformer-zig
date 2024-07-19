const std = @import("std");
const print = std.debug.print;
const BoundedQueue = @import("./utils.zig").BoundedQueue;

/// hard limit for nested quotes;
/// example markdown-sequence: **__*_[**__*_`hi`_*__*](#hi)_*__**
/// example html-nesting: strong > strong > em > em > a > strong > strong > em > em > code
const MAX_NEST_DEPTH = 10;

pub fn main() void {}

test "hello world" {
    var output = std.ArrayList(u8).init(std.testing.allocator);
    defer output.deinit();

    var markdown_content = std.ArrayList(u8).init(std.testing.allocator);
    defer markdown_content.deinit();
    try markdown_content.appendSlice(
        \\Hello world!
        \\
        \\# Headers be heading, right?
        \\
        \\**This side-quest** has main-quest potential.
    );
    var html_stream = HtmlStream.new(std.testing.allocator, CharStream.new(markdown_content));

    var n: usize = 0;
    while (try html_stream.next(std.testing.allocator)) |html_token| {
        defer html_token.deinit();
        if (12 < n) break;
        defer n += 1;

        const html_string = html_token.serialize();
        try output.appendSlice(html_string);
        if (html_token.kind() == .close) try output.append('\n');
    }
    print("\n\n" ++ "-HTML-OUTPUT" ++ "-" ** 68 ++ "\n\n{s}\n" ++ "-" ** 80 ++ "\n", .{output.items});
}

const CharStream = struct {
    buffer: std.ArrayList(u8),
    idx: usize,
    remaining_length: usize,

    const Self = @This();

    fn new(buffer: std.ArrayList(u8)) Self {
        return .{ .buffer = buffer, .idx = 0, .remaining_length = buffer.items.len };
    }

    fn next(self: *Self) ?u8 {
        if (self.buffer.items.len <= self.idx) return null;
        const char = self.buffer.items[self.idx];
        self.idx += 1;
        self.remaining_length -= 1;
        return char;
    }

    fn peek(self: Self) ?u8 {
        return self.peekOffset(0);
    }

    fn peekOffset(self: Self, offset: usize) ?u8 {
        if (self.remaining_length <= offset) return null;
        return self.buffer.items[self.idx + offset];
    }

    fn peekRemainder(self: Self) ?[]const u8 {
        if (self.buffer.items.len <= self.idx) return null;
        return self.buffer.items[self.idx..];
    }
};

const HtmlStream = struct {
    scratch_allocator: std.mem.Allocator,
    md_stream: CharStream,
    html_queue: BoundedQueue(HtmlToken, MAX_NEST_DEPTH),
    block_context: ?BlockContext = null,

    const Self = @This();

    fn new(scratch_allocator: std.mem.Allocator, md_stream: CharStream) Self {
        return .{
            .scratch_allocator = scratch_allocator,
            .md_stream = md_stream,
            .html_queue = BoundedQueue(HtmlToken, MAX_NEST_DEPTH).new(),
        };
    }

    fn next(self: *Self, output_allocator: std.mem.Allocator) !?HtmlToken {
        if (self.html_queue.take()) |html_token| {
            return html_token;
        }
        const block_context = self.block_context orelse return self.nextNoContext();

        switch (block_context) {
            .p => try self.parseParagraph(output_allocator),
            .h1, .h2, .h3, .h4, .h5, .h6 => try self.parseHeader(output_allocator),
            .pre => self.parseCodeBlock(),
            .blockquote => self.parseQuoteBlock(),
            .ul, .ol => self.parseListBlock(),
        }
        return self.html_queue.take();
    }

    fn nextNoContext(self: *Self) ?HtmlToken {
        self.skipSpaceCharacters();

        const remaining_slice = self.md_stream.peekRemainder() orelse return null;
        const block_context = BlockContext.from(remaining_slice) orelse return null;

        for (0..block_context.modifierLen()) |_| _ = self.md_stream.next();

        self.block_context = block_context;
        return block_context.tag(.open);
    }

    fn parseParagraph(self: *Self, output_allocator: std.mem.Allocator) !void {
        std.debug.assert(self.html_queue.len == 0);
        std.debug.assert(self.block_context.? == .p);

        try self.parseInlineText(output_allocator);

        try self.html_queue.put(.last, tag: {
            const remainder = self.md_stream.peekRemainder() orelse break :tag self.popBlockContextCloseTag();

            if (remainder[0] == '\n' or HtmlToken.startsWithHeader(remainder))
                break :tag self.popBlockContextCloseTag();

            break :tag .br;
        });
    }

    fn skipSpaceCharacters(self: *Self) void {
        while (self.md_stream.peek()) |char| switch (char) {
            ' ', '\t', '\n' => _ = self.md_stream.next(),
            else => break,
        };
    }

    fn parseInlineText(self: *Self, output_allocator: std.mem.Allocator) !void {
        std.debug.assert(self.html_queue.len == 0);
        std.debug.assert(self.block_context != null);

        self.skipSpaceCharacters();

        var text = std.ArrayList(u8).init(output_allocator);
        text.deinit();

        while (self.md_stream.next()) |char| {
            if (char == '\n') break;
            try text.append(char);
        }

        try self.html_queue.put(.last, try HtmlToken.text(output_allocator, &text));
    }

    fn parseHeader(self: *Self, output_allocator: std.mem.Allocator) !void {
        std.debug.assert(self.html_queue.len == 0);
        std.debug.assert(correct_block_context: {
            break :correct_block_context switch (self.block_context.?) {
                .h1, .h2, .h3, .h4, .h5, .h6 => true,
                else => false,
            };
        });

        try self.parseInlineText(output_allocator);
        try self.html_queue.put(.last, self.popBlockContextCloseTag());
    }

    fn popBlockContextCloseTag(self: *Self) HtmlToken {
        const block_context = self.block_context.?;
        const html_token = block_context.tag(.close);
        self.block_context = null;
        return html_token;
    }

    fn parseCodeBlock(self: Self) void {
        _ = self;
    }

    fn parseQuoteBlock(self: Self) void {
        _ = self;
    }

    fn parseListBlock(self: Self) void {
        _ = self;
    }
};

const BlockContext = enum {
    p,
    h1,
    h2,
    h3,
    h4,
    h5,
    h6,
    pre,
    blockquote,
    ul,
    ol,

    const Self = @This();

    fn from(chars: []const u8) ?Self {
        if (chars.len == 0) return null;

        var i: usize = 0;
        while (i < chars.len) : (i += 1) switch (chars[i]) {
            ' ', '\t', '\n' => continue,
            else => break,
        } else return null;

        const significant_chars = chars[i..];
        is_not_paragraph: {
            switch (significant_chars[0]) {
                '#' => {
                    var count: u3 = 1;
                    for (significant_chars[1..]) |char| switch (char) {
                        '#' => {
                            count += 1;
                            if (6 < count) break :is_not_paragraph;
                        },
                        ' ', '\t', '\n' => return Self.fromHeaderSize(count),
                        else => break :is_not_paragraph,
                    };
                },
                '`' => {
                    var count: u2 = 1;
                    for (significant_chars) |char| switch (char) {
                        '`' => {
                            count += 1;
                            if (count == 3) return .pre;
                        },
                        else => break :is_not_paragraph,
                    };
                },
                '>' => return .blockquote,
                '-' => if (significant_chars[1] == ' ') return .ul,
                '0'...'9' => {
                    for (significant_chars) |char| switch (char) {
                        '0'...'9' => continue,
                        '.' => return .ol,
                        else => break :is_not_paragraph,
                    };
                },
                else => break :is_not_paragraph,
            }
        }
        return .p;
    }

    fn fromHeaderSize(size: u3) Self {
        return switch (size) {
            1 => .h1,
            2 => .h2,
            3 => .h3,
            4 => .h4,
            5 => .h5,
            6 => .h6,
            else => .p,
        };
    }

    fn tag(self: Self, kind: enum { open, close }) HtmlToken {
        return switch (self) {
            .p => switch (kind) {
                .open => .p_,
                .close => ._p,
            },
            .h1 => switch (kind) {
                .open => .h1_,
                .close => ._h1,
            },
            .h2 => switch (kind) {
                .open => .h2_,
                .close => ._h2,
            },
            .h3 => switch (kind) {
                .open => .h3_,
                .close => ._h3,
            },
            .h4 => switch (kind) {
                .open => .h4_,
                .close => ._h4,
            },
            .h5 => switch (kind) {
                .open => .h5_,
                .close => ._h5,
            },
            .h6 => switch (kind) {
                .open => .h6_,
                .close => ._h6,
            },
            .pre => switch (kind) {
                .open => .pre_,
                .close => ._pre,
            },
            .blockquote => switch (kind) {
                .open => .blockquote_,
                .close => ._blockquote,
            },
            .ul => switch (kind) {
                .open => .ul_,
                .close => ._ul,
            },
            .ol => switch (kind) {
                .open => .ol_,
                .close => ._ol,
            },
        };
    }

    /// number of significant modifier-characters
    fn modifierLen(self: Self) usize {
        return switch (self) {
            .p => "".len,
            .h1 => "# ".len,
            .h2 => "## ".len,
            .h3 => "### ".len,
            .h4 => "#### ".len,
            .h5 => "##### ".len,
            .h6 => "###### ".len,
            .pre => "```".len, // but what if there's a language indicator?
            .blockquote => ">".len,
            .ul => "- ".len,
            .ol => @panic("yo time to deal with this, maybe tagged union?"),
        };
    }
};

const HtmlToken = union(HtmlTokenTag) {
    text: struct { allocator: std.mem.Allocator, content: []const u8 },
    br,
    p_,
    _p,
    a_: struct { allocator: std.mem.Allocator, href: []const u8 },
    _a,
    h1_,
    _h1,
    h2_,
    _h2,
    h3_,
    _h3,
    h4_,
    _h4,
    h5_,
    _h5,
    h6_,
    _h6,
    pre_,
    _pre,
    blockquote_,
    _blockquote,
    ul_,
    _ul,
    ol_,
    _ol,
    li_,
    _li,
    em_,
    _em,
    strong_,
    _strong,
    code_,
    _code,

    const Self = @This();

    fn deinit(self: Self) void {
        switch (self) {
            .text => |t| t.allocator.free(t.content),
            else => {},
        }
    }

    fn text(allocator: std.mem.Allocator, text_buffer: *std.ArrayList(u8)) !HtmlToken {
        return .{ .text = .{ .allocator = allocator, .content = try text_buffer.toOwnedSlice() } };
    }

    fn serialize(self: Self) []const u8 {
        return switch (self) {
            .text => |t| t.content,
            .br => "<br>",
            .p_ => "<p>",
            ._p => "</p>",
            .a_ => "<a>",
            ._a => "</a>",
            .h1_ => "<h1>",
            ._h1 => "</h1>",
            .h2_ => "<h2>",
            ._h2 => "</h2>",
            .h3_ => "<h3>",
            ._h3 => "</h3>",
            .h4_ => "<h4>",
            ._h4 => "</h4>",
            .h5_ => "<h5>",
            ._h5 => "</h5>",
            .h6_ => "<h6>",
            ._h6 => "</h6>",
            .pre_ => "<pre>",
            ._pre => "</pre>",
            .blockquote_ => "<blockquote>",
            ._blockquote => "</blockquote>",
            .ul_ => "<ul>",
            ._ul => "</ul>",
            .ol_ => "<ol>",
            ._ol => "</ol>",
            .li_ => "<li>",
            ._li => "</li>",
            .em_ => "<em>",
            ._em => "</em>",
            .strong_ => "<strong>",
            ._strong => "</strong>",
            .code_ => "<code>",
            ._code => "</code>",
        };
    }

    fn kind(self: Self) enum { open, close, solo } {
        const tagName = @tagName(self);
        if (tagName[tagName.len - 1] == '_') return .open;
        if (tagName[0] == '_') return .close;
        return .solo;
    }

    fn startsWithHeader(string: []const u8) bool {
        var count: u3 = 0; // maximum count is 7, because h6 is highest header number
        for (string) |char| switch (char) {
            ' ', '\t' => {
                if (count == 0) continue;
                return true;
            },
            '#' => {
                count += 1;
                if (count > 6) return false;
            },
            else => return false,
        };
        return false;
    }
};

const HtmlTokenTag = enum {
    text,
    br,
    p_,
    _p,
    a_,
    _a,
    h1_,
    _h1,
    h2_,
    _h2,
    h3_,
    _h3,
    h4_,
    _h4,
    h5_,
    _h5,
    h6_,
    _h6,
    pre_,
    _pre,
    blockquote_,
    _blockquote,
    ul_,
    _ul,
    ol_,
    _ol,
    li_,
    _li,
    em_,
    _em,
    strong_,
    _strong,
    code_,
    _code,
};
