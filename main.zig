const std = @import("std");

pub fn main() !void {
    std.debug.print("hihi", .{});
}

const Buffer = []const u8;
const BufferIndex = usize;

const Token = union(TokenTag) {
    init: void,
    paragraph_part: []const u8,
    paragraph_end: void,
    header: []const u8,
};

const TokenTag = enum {
    init,
    paragraph_part,
    paragraph_end,
    header,
};

const ParseError = error{IncompleteToken};

const MarkdownTokensIterator = struct {
    buffer: Buffer,
    index: BufferIndex,
    last_token: TokenTag,

    const Self = @This();
    const TokenResult = union(TokenResultTag) { token: Token, err: ParseError };
    const TokenResultTag = enum { token, err };

    /// Returns the next token or null when no next token
    pub fn next(self: *Self) ?TokenResult {
        if (self.index == self.buffer.len) return null;

        std.debug.print("index: {?}; buffer_len: {?}\n", .{ self.index, self.buffer.len });
        const token_start = TokenStart.find(self.last_token, self.buffer, self.index) catch |err| switch (err) {
            error.EndOfBuffer => return null,
            // else => return TokenResult{ .err = err },
        };
        const token_end = TokenEnd.find(token_start.tag, self.buffer, token_start.index) catch |err| {
            return TokenResult{ .err = err };
        };

        if (token_start.tag == .paragraph_end) {
            std.debug.print("tag: {?}\n", .{token_start.tag});
        } else {
            std.debug.print("tag: {?}\ncontent[{?}]: \"{s}\"\n", .{ token_start.tag, token_end.content.?.len, token_end.content.? });
        }
        self.index = token_end.index + 1;
        std.debug.print("new index: {?}\n", .{self.index});
        self.last_token = token_start.tag;
        return TokenResult{ .token = createToken(token_start.tag, token_end.content) };
    }
};

const TokenStart = struct {
    tag: TokenTag,
    index: BufferIndex,

    fn find(last_token: TokenTag, buffer: Buffer, index: BufferIndex) !TokenStart {
        switch (last_token) {
            .init, .paragraph_end, .header => {
                var start = index;
                return while (start < buffer.len) {
                    switch (buffer[start]) {
                        '\n', '\t', ' ' => start += 1,
                        '#' => break TokenStart{ .tag = .header, .index = start + 1 },
                        else => break TokenStart{ .tag = .paragraph_part, .index = start },
                    }
                } else error.EndOfBuffer;
            },
            .paragraph_part => {
                var start = index;
                return while (start < buffer.len) {
                    switch (buffer[start]) {
                        '\t', ' ' => start += 1,
                        '\n' => break TokenStart{ .tag = .paragraph_end, .index = start },
                        '#' => break TokenStart{ .tag = .header, .index = start + 1 },
                        else => break TokenStart{ .tag = .paragraph_part, .index = start },
                    }
                } else error.EndOfBuffer;
            },
        }
    }
};

const TokenEnd = struct {
    content: ?Buffer,
    index: BufferIndex,

    fn find(current_token: TokenTag, buffer: Buffer, start: BufferIndex) !TokenEnd {
        switch (current_token) {
            .paragraph_part => {
                var end = start;
                var content_end = end;
                return while (end < buffer.len) {
                    switch (buffer[end]) {
                        '\n' => break TokenEnd{ .content = buffer[start..content_end], .index = end },
                        '\t', ' ' => end += 1,
                        else => {
                            end += 1;
                            content_end = end;
                        },
                    }
                } else TokenEnd{ .content = buffer[start..end], .index = end };
            },
            .paragraph_end => {
                var end = start;
                return while (end < buffer.len) {
                    switch (buffer[end]) {
                        '\n', '\t', ' ' => end += 1,
                        else => break TokenEnd{ .content = null, .index = end - 1 },
                    }
                } else TokenEnd{ .content = buffer[start..end], .index = end };
            },
            .header => {
                var start_content = start;
                while (start_content < buffer.len) {
                    switch (buffer[start_content]) {
                        '\t', ' ' => start_content += 1,
                        else => break,
                    }
                }
                var end = start_content;
                var end_content = end;
                return while (end < buffer.len) {
                    switch (buffer[end]) {
                        '\n' => break TokenEnd{ .content = buffer[start_content..end_content], .index = end },
                        '\t', ' ' => end += 1,
                        else => {
                            end += 1;
                            end_content = end;
                        },
                    }
                } else TokenEnd{ .content = buffer[start_content..end_content], .index = end };
            },
            else => unreachable,
        }
    }
};

fn createToken(tag: TokenTag, content: ?Buffer) Token {
    return switch (tag) {
        .paragraph_part => Token{ .paragraph_part = content.? },
        .paragraph_end => Token.paragraph_end,
        .header => Token{ .header = content.? },
        else => unreachable,
    };
}

fn parse(token_list: *std.ArrayList(Token), buffer: []const u8) !void {
    var it = MarkdownTokensIterator{
        .buffer = buffer,
        .index = 0,
        .last_token = .init,
    };
    std.debug.print("\n" ++ "=" ** 80 ++ "\n", .{});
    while (it.next()) |token_result| {
        std.debug.print("-" ** 80 ++ "\n", .{});
        switch (token_result) {
            .token => |token| try token_list.append(token),
            .err => |err| return err,
        }
    }
    std.debug.print("\n" ++ "_" ** 80 ++ "\n", .{});
}

test "one paragraph, one line" {
    var token_list = std.ArrayList(Token).init(std.testing.allocator);
    defer token_list.deinit();

    const content = "this is some text";
    try parse(&token_list, content);
    try expectEqualTokens(token_list, &[_]Token{Token{ .paragraph_part = content }});
}

test "one paragraph, two lines" {
    var token_list = std.ArrayList(Token).init(std.testing.allocator);
    defer token_list.deinit();

    const line1 = "first line";
    const line2 = "second line";
    try parse(&token_list, line1 ++ "\n" ++ line2);
    try expectEqualTokens(token_list, &[_]Token{
        Token{ .paragraph_part = line1 }, Token{ .paragraph_part = line2 },
    });
}

test "one paragraph, two lines with padding" {
    var token_list = std.ArrayList(Token).init(std.testing.allocator);
    defer token_list.deinit();

    const line1 = "first line";
    const line2 = "second line";
    try parse(&token_list, line1 ++ "  \n  " ++ line2);
    try expectEqualTokens(token_list, &[_]Token{
        Token{ .paragraph_part = line1 }, Token{ .paragraph_part = line2 },
    });
}

test "two paragraphs with padding" {
    var token_list = std.ArrayList(Token).init(std.testing.allocator);
    defer token_list.deinit();

    const line1 = "first paragraph";
    const line2 = "second paragraph";
    try parse(&token_list, line1 ++ " \n \n  " ++ line2);
    try expectEqualTokens(token_list, &[_]Token{
        Token{ .paragraph_part = line1 }, Token.paragraph_end, Token{ .paragraph_part = line2 },
    });
}

test "one header" {
    var token_list = std.ArrayList(Token).init(std.testing.allocator);
    defer token_list.deinit();

    const content = "this is a header";
    try parse(&token_list, "#" ++ content);
    try expectEqualTokens(token_list, &[_]Token{Token{ .header = content }});
}

test "one header with padding" {
    var token_list = std.ArrayList(Token).init(std.testing.allocator);
    defer token_list.deinit();

    const content = "this is a header with multiple  spaces sometimes hehe";
    try parse(&token_list, "# \t" ++ content ++ "  ");
    try expectEqualTokens(token_list, &[_]Token{Token{ .header = content }});
}

test "one header, surrounded by a paragraph" {
    var token_list = std.ArrayList(Token).init(std.testing.allocator);
    defer token_list.deinit();

    const pre_header_content = "pre-header stuff";
    const header_content = "this is a header with multiple  spaces sometimes hehe";
    const post_header_content = "paragraph part of header";
    try parse(&token_list, pre_header_content ++ "\n" ++ "# " ++ header_content ++ "\n" ++ post_header_content);
    try expectEqualTokens(token_list, &[_]Token{
        Token{ .paragraph_part = pre_header_content },  Token{ .header = header_content },
        Token{ .paragraph_part = post_header_content },
    });
}

test "one header, surrounded by a paragraph with all kinds of padding" {
    var token_list = std.ArrayList(Token).init(std.testing.allocator);
    defer token_list.deinit();

    const pre_header_content = "pre-header stuff";
    const header_content = "this is a header with multiple  spaces sometimes hehe";
    const post_header_content = "paragraph part of header";
    try parse(&token_list, pre_header_content ++ "\n \n" ++ "# " ++ header_content ++ " \n\t" ++ post_header_content);
    try expectEqualTokens(token_list, &[_]Token{
        Token{ .paragraph_part = pre_header_content }, Token.paragraph_end,
        Token{ .header = header_content },             Token{ .paragraph_part = post_header_content },
    });
}

fn expectEqualTokens(token_list: std.ArrayList(Token), expected_tokens: []const Token) !void {
    try std.testing.expectEqualDeep(expected_tokens, token_list.items);
}
