const std = @import("std");

pub fn main() !void {}

const Buffer = []const u8;
const BufferIndex = usize;

const Token = union(TokenTag) {
    init: void,
    paragraph_part: []const u8,
    paragraph_end: void,
    h1: []const u8,
    h2: []const u8,
    h3: []const u8,
    h4: []const u8,
    h5: []const u8,
    h6: []const u8,

    fn debugInfo(self: Token, allocator: std.mem.Allocator) ![]const u8 {
        const name = @tagName(self);
        const content = switch (self) {
            .init, .paragraph_end => "",
            .paragraph_part, .h1, .h2, .h3, .h4, .h5, .h6 => |str| str,
        };
        return std.fmt.allocPrint(allocator, "[{s}] {s}", .{ name, content });
    }
};

const TokenTag = enum { init, paragraph_part, paragraph_end, h1, h2, h3, h4, h5, h6 };

const ParseError = error{ IncompleteToken, UndefinedHeaderLevel };

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

        const token_start = TokenStart.find(self.last_token, self.buffer, self.index) catch |err| switch (err) {
            error.EndOfBuffer => return null,
            error.UndefinedHeaderLevel => |e| return TokenResult{ .err = e },
        };
        const token_end = TokenEnd.find(token_start.tag, self.buffer, token_start.index) catch |err| {
            return TokenResult{ .err = err };
        };

        self.index = token_end.index + 1;
        self.last_token = token_start.tag;
        return TokenResult{ .token = createToken(token_start.tag, token_end.content) };
    }
};

const TokenStart = struct {
    tag: TokenTag,
    index: BufferIndex,

    fn find(last_token: TokenTag, buffer: Buffer, index: BufferIndex) !TokenStart {
        switch (last_token) {
            .init, .paragraph_end, .h1, .h2, .h3, .h4, .h5, .h6 => {
                var start = index;
                return while (start < buffer.len) {
                    switch (buffer[start]) {
                        '\n', '\t', ' ' => start += 1,
                        '#' => break initHeader(buffer, start),
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
                        '#' => break initHeader(buffer, start),
                        else => break TokenStart{ .tag = .paragraph_part, .index = start },
                    }
                } else error.EndOfBuffer;
            },
        }
    }

    fn initHeader(buffer: Buffer, start: BufferIndex) !TokenStart {
        std.debug.assert(buffer[start] == '#');
        var header_level: u3 = 1;
        while (buffer[start + header_level] == '#') : (header_level += 1) {}
        return TokenStart{
            .tag = switch (header_level) {
                1 => .h1,
                2 => .h2,
                3 => .h3,
                4 => .h4,
                5 => .h5,
                6 => .h6,
                else => return error.UndefinedHeaderLevel,
            },
            .index = start + header_level,
        };
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
            .h1, .h2, .h3, .h4, .h5, .h6 => return initHeader(buffer, start),
            else => unreachable,
        }
    }

    fn initHeader(buffer: Buffer, start: BufferIndex) TokenEnd {
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
    }
};

fn createToken(tag: TokenTag, content: ?Buffer) Token {
    return switch (tag) {
        .paragraph_part => Token{ .paragraph_part = content.? },
        .paragraph_end => Token.paragraph_end,
        .h1 => Token{ .h1 = content.? },
        .h2 => Token{ .h2 = content.? },
        .h3 => Token{ .h3 = content.? },
        .h4 => Token{ .h4 = content.? },
        .h5 => Token{ .h5 = content.? },
        .h6 => Token{ .h6 = content.? },
        else => unreachable,
    };
}

fn parse(token_list: *std.ArrayList(Token), buffer: []const u8) !void {
    var it = MarkdownTokensIterator{
        .buffer = buffer,
        .index = 0,
        .last_token = .init,
    };
    while (it.next()) |token_result| {
        switch (token_result) {
            .token => |token| try token_list.append(token),
            .err => |err| return err,
        }
    }
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
    try expectEqualTokens(token_list, &[_]Token{Token{ .h1 = content }});
}

test "one header with padding" {
    var token_list = std.ArrayList(Token).init(std.testing.allocator);
    defer token_list.deinit();

    const content = "this is a header with multiple  spaces sometimes hehe";
    try parse(&token_list, "# \t" ++ content ++ "  ");
    try expectEqualTokens(token_list, &[_]Token{Token{ .h1 = content }});
}

test "one header, surrounded by a paragraph" {
    var token_list = std.ArrayList(Token).init(std.testing.allocator);
    defer token_list.deinit();

    const pre_header_content = "pre-header stuff";
    const header_content = "this is a header with multiple  spaces sometimes hehe";
    const post_header_content = "paragraph part of header";
    try parse(&token_list, pre_header_content ++ "\n" ++ "# " ++ header_content ++ "\n" ++ post_header_content);
    try expectEqualTokens(token_list, &[_]Token{
        Token{ .paragraph_part = pre_header_content },  Token{ .h1 = header_content },
        Token{ .paragraph_part = post_header_content },
    });
}

test "one header, surrounded by a paragraph with all kinds of padding" {
    var token_list = std.ArrayList(Token).init(std.testing.allocator);
    defer token_list.deinit();

    const pre_h1_content = "pre-header stuff";
    const h1_content = "this is a header with multiple  spaces sometimes hehe";
    const post_h1_content = "paragraph part of header";
    try parse(&token_list, pre_h1_content ++ "\n \n" ++ "# " ++ h1_content ++ " \n\t" ++ post_h1_content);
    try expectEqualTokens(token_list, &[_]Token{
        Token{ .paragraph_part = pre_h1_content }, Token.paragraph_end,
        Token{ .h1 = h1_content },                 Token{ .paragraph_part = post_h1_content },
    });
}

test "multi-level headers" {
    var token_list = std.ArrayList(Token).init(std.testing.allocator);
    defer token_list.deinit();

    const pre_h1_content = "pre-h1 stuff";
    const h1_content = "this is a h1 with multiple  spaces sometimes hehe";
    const post_h1_content = "paragraph part of h1";
    const h2_content = "this is a h2 with multiple  spaces sometimes hehe";
    const post_h2_content = "paragraph part of h2";
    const h3_content = "this is a h3 with multiple  spaces sometimes hehe";
    const post_h3_content = "paragraph part of h3";
    const h4_content = "this is a h4 with multiple  spaces sometimes hehe";
    const post_h4_content = "paragraph part of h4";
    const h5_content = "this is a h5 with multiple  spaces sometimes hehe";
    const post_h5_content = "paragraph part of h5";
    const h6_content = "this is a h6 with multiple  spaces sometimes hehe";
    const post_h6_content = "paragraph part of h6";
    try parse(&token_list, "" ++
        pre_h1_content ++ "\n \n" ++
        "# " ++ h1_content ++ " \n\t" ++ post_h1_content ++ "\n\t" ++
        "##" ++ h2_content ++ "\n\t" ++ post_h2_content ++ "\n\t" ++
        "###" ++ h3_content ++ "\n\t" ++ post_h3_content ++ "\n\t" ++
        "####" ++ h4_content ++ "\n\t" ++ post_h4_content ++ "\n\t" ++
        "#####" ++ h5_content ++ "\n\t" ++ post_h5_content ++ "\n\t" ++
        "######" ++ h6_content ++ "\n\t" ++ post_h6_content);
    try expectEqualTokens(token_list, &[_]Token{
        Token{ .paragraph_part = pre_h1_content }, Token.paragraph_end,
        Token{ .h1 = h1_content },                 Token{ .paragraph_part = post_h1_content },
        Token{ .h2 = h2_content },                 Token{ .paragraph_part = post_h2_content },
        Token{ .h3 = h3_content },                 Token{ .paragraph_part = post_h3_content },
        Token{ .h4 = h4_content },                 Token{ .paragraph_part = post_h4_content },
        Token{ .h5 = h5_content },                 Token{ .paragraph_part = post_h5_content },
        Token{ .h6 = h6_content },                 Token{ .paragraph_part = post_h6_content },
    });
}

fn expectEqualTokens(token_list: std.ArrayList(Token), expected_tokens: []const Token) !void {
    const received_tokens = token_list.items;
    std.testing.expectEqualDeep(expected_tokens, received_tokens) catch |err| {
        std.debug.print("—" ** 80 ++ "\n", .{});
        var i: usize = 0;
        const len = @max(received_tokens.len, expected_tokens.len);
        while (i < len) : (i += 1) {
            if (i < received_tokens.len) {
                const received = received_tokens[i];
                const receivedInfo = try received.debugInfo(std.testing.allocator);
                defer std.testing.allocator.free(receivedInfo);
                std.debug.print("received {s}\n", .{receivedInfo});
            } else std.debug.print("received none\n", .{});

            if (i < expected_tokens.len) {
                const expected = expected_tokens[i];
                const expectedInfo = try expected.debugInfo(std.testing.allocator);
                defer std.testing.allocator.free(expectedInfo);
                std.debug.print("expected {s}\n", .{expectedInfo});
            } else std.debug.print("expected none\n", .{});
        }
        std.debug.print("—" ** 80 ++ "\n", .{});
        std.debug.print("{any}\n", .{err});
        std.debug.print("—" ** 80 ++ "\n", .{});
        return err;
    };
}
