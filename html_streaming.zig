const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;
const MdToken = @import("./md_streaming.zig").Token;
const MdTokenStream = @import("./md_streaming.zig").TokenStream;

const FromMarkdownStream = struct {
    token_stream: *MdTokenStream,
    ancestry: std.ArrayList(ElementType),

    current_parent: ElementType = .body,
    next_html_token: ?HtmlToken = null,
    next_unprocessed_token: ?MdToken = null,
    close_parent: bool = false,
    close_stream: bool = false,

    const Self = @This();

    pub fn init(token_stream: *MdTokenStream, allocator: std.mem.Allocator) !Self {
        var ancestry = std.ArrayList(ElementType).init(allocator);
        try ancestry.append(.body);
        return .{
            .token_stream = token_stream,
            .ancestry = ancestry,
        };
    }

    pub fn deinit(self: Self) void {
        self.ancestry.deinit();
    }

    pub fn next(self: *Self, allocator: std.mem.Allocator) !?HtmlToken {
        if (self.next_html_token) |token| {
            self.next_html_token = null;
            return token;
        }

        if (self.close_parent) return self.closeParent();
        if (self.close_stream) return self.closeStream();

        return switch (self.current_parent) {
            .body => try self.nextFromBody(),
            .paragraph => try self.nextFromParagraph(allocator),
        };
    }

    fn closeParent(self: *Self) HtmlToken {
        assert(self.ancestry.items.len > 0);
        self.close_parent = false;
        const parent_to_close = self.ancestry.pop();
        self.current_parent = self.ancestry.getLast();
        return parent_to_close.closingToken();
    }

    fn closeStream(self: *Self) ?HtmlToken {
        self.close_stream = true;
        if (self.ancestry.items.len == 1) return null;

        const parent_to_close = self.ancestry.pop();
        self.current_parent = self.ancestry.getLast();
        return parent_to_close.closingToken();
    }

    fn nextFromBody(self: *Self) !?HtmlToken {
        while (self.nextUnprocessedToken()) |token| {
            switch (token) {
                .alphanumerical => {
                    try self.ancestry.append(.paragraph);
                    self.current_parent = .paragraph;
                    self.next_unprocessed_token = token;
                    return HtmlToken.paragraph_opening;
                },
                .space => {},
                .symbol => @panic("dem symbols maine"),
            }
        }
        return self.closeStream() orelse null;
    }

    fn nextFromParagraph(self: *Self, allocator: std.mem.Allocator) !?HtmlToken {
        var text_buffer = std.ArrayList(u8).init(allocator);
        defer text_buffer.deinit();

        ingestion: while (self.nextUnprocessedToken()) |token| {
            switch (token) {
                .space => |content| {
                    var new_line_count: usize = 0;
                    for (content) |char| {
                        if (char == '\n') new_line_count += 1;
                    }

                    switch (new_line_count) {
                        0 => {
                            try text_buffer.append(' ');
                            continue :ingestion;
                        },
                        1 => {
                            self.next_html_token = HtmlToken.line_break;
                            break :ingestion;
                        },
                        else => {
                            self.close_parent = true;
                            break :ingestion;
                        },
                    }
                },

                .symbol => @panic("dem symbols maine"),

                .alphanumerical => |content| {
                    print("content: {s}\n", .{content});
                    for (content) |char| try text_buffer.append(char);
                },
            }
        }
        if (text_buffer.items.len > 0) {
            self.close_parent = true;
            return HtmlToken{ .text_node = try toNewOwner(allocator, &text_buffer) };
        }

        print("bye bye\n", .{});
        return null;
    }

    fn nextUnprocessedToken(self: *Self) ?MdToken {
        if (self.next_unprocessed_token) |token| {
            self.next_unprocessed_token = null;
            return token;
        }
        return self.token_stream.next();
    }
};

fn toNewOwner(allocator: std.mem.Allocator, text_buffer: *std.ArrayList(u8)) !std.ArrayList(u8) {
    const slice = try text_buffer.toOwnedSlice();
    return std.ArrayList(u8).fromOwnedSlice(allocator, slice);
}

const Tree = struct { type: ElementType };

const ElementType = enum {
    body,
    paragraph,

    fn closingToken(self: ElementType) HtmlToken {
        return switch (self) {
            .paragraph => HtmlToken.paragraph_closing,
            .body => @panic("ain't go need for no closing body yet yo"),
        };
    }
};

const HtmlToken = union(HtmlTag) {
    line_break,
    paragraph_opening,
    paragraph_closing,
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
    paragraph_opening,
    paragraph_closing,
    text_node,
};

test "test two next calls for one paragraph" {
    print("\n\n", .{});
    var tokens = [_]MdToken{
        MdToken{ .alphanumerical = "hello" },
        MdToken{ .space = " " },
        MdToken{ .alphanumerical = "moto" },
        MdToken{ .space = "\n" },
        // MdToken{ .symbol = "#" },
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
    var parser = try FromMarkdownStream.init(&md_token_stream, std.testing.allocator);
    defer parser.deinit();

    while (try parser.next(std.testing.allocator)) |token| {
        defer token.deinit();
        print("parsed: {any}\n", .{token});
    }
}
