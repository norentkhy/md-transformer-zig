const std = @import("std");

pub const TokenStream = union(TokenStreamTag) {
    text: FromText,
    tokens: FromTokens,

    const Self = @This();

    pub fn next(self: *Self) ?Token {
        return switch (self.*) {
            inline else => |*s| s.next(),
        };
    }

    pub fn fromText(text: []const u8) Self {
        var stream = Self{ .text = FromText{ .text = text } };
        return &stream;
    }

    pub fn fromTokens(tokens: []const Token) Self {
        return Self{ .tokens = FromTokens{ .tokens = tokens } };
    }
};

const TokenStreamTag = enum { text, tokens };

const FromText = struct {
    text: []const u8,
    idx: usize = 0,

    const Self = @This();

    fn next(self: *Self) ?Token {
        if (self.idx >= self.text.len) return null;

        const tokenTag = self.currentCharType();
        const start = self.idx;
        while (self.idx < self.text.len and self.currentCharType() == tokenTag) : (self.idx += 1) {}
        return Token.create(tokenTag, self.text[start..self.idx]);
    }

    fn currentCharType(self: Self) TokenTag {
        return switch (self.text[self.idx]) {
            'a'...'z', 'A'...'Z' => .alphanumerical,
            ' ', '\t', '\n', '\r' => .space,
            else => .symbol,
        };
    }
};

const FromTokens = struct {
    tokens: []const Token,
    idx: usize = 0,
    const Self = @This();

    fn next(self: *Self) ?Token {
        if (self.idx >= self.tokens.len) return null;

        const token = self.tokens[self.idx];
        self.idx += 1;
        return token;
    }
};

pub const Token = union(TokenTag) {
    alphanumerical: []const u8,
    space: []const u8,
    symbol: []const u8,

    pub fn create(tag: TokenTag, content: []const u8) Token {
        return switch (tag) {
            .alphanumerical => Token{ .alphanumerical = content },
            .space => Token{ .space = content },
            .symbol => Token{ .symbol = content },
        };
    }

    pub fn debugInfo(self: Token) []const u8 {
        return switch (self) {
            .alphanumerical => |content| content,
            .space => |content| content,
            .symbol => |content| content,
        };
    }
};

const TokenTag = enum { alphanumerical, space, symbol };

test "FromText" {
    const text =
        \\hello moto
        \\# moto moto
        \\moo desu desu **`kawaiii`**_
        \\
        \\issa new paragraph
        \\gotta tell you about shell-scripts man
        \\```sh
        \\echo hello world;
        \\```
    ;

    var token_list = std.ArrayList(Token).init(std.testing.allocator);
    defer token_list.deinit();
    var token_stream = FromText{ .text = text };
    while (token_stream.next()) |token| {
        try token_list.append(token);
    }

    try expectEqualTokens(
        token_list,
        &[_]Token{
            Token{ .alphanumerical = "hello" },
            Token{ .space = " " },
            Token{ .alphanumerical = "moto" },
            Token{ .space = "\n" },
            Token{ .symbol = "#" },
            Token{ .space = " " },
            Token{ .alphanumerical = "moto" },
            Token{ .space = " " },
            Token{ .alphanumerical = "moto" },
            Token{ .space = "\n" },
            Token{ .alphanumerical = "moo" },
            Token{ .space = " " },
            Token{ .alphanumerical = "desu" },
            Token{ .space = " " },
            Token{ .alphanumerical = "desu" },
            Token{ .space = " " },
            Token{ .symbol = "**`" },
            Token{ .alphanumerical = "kawaiii" },
            Token{ .symbol = "`**_" },
            Token{ .space = "\n\n" },
            Token{ .alphanumerical = "issa" },
            Token{ .space = " " },
            Token{ .alphanumerical = "new" },
            Token{ .space = " " },
            Token{ .alphanumerical = "paragraph" },
            Token{ .space = "\n" },
            Token{ .alphanumerical = "gotta" },
            Token{ .space = " " },
            Token{ .alphanumerical = "tell" },
            Token{ .space = " " },
            Token{ .alphanumerical = "you" },
            Token{ .space = " " },
            Token{ .alphanumerical = "about" },
            Token{ .space = " " },
            Token{ .alphanumerical = "shell" },
            Token{ .symbol = "-" },
            Token{ .alphanumerical = "scripts" },
            Token{ .space = " " },
            Token{ .alphanumerical = "man" },
            Token{ .space = "\n" },
            Token{ .symbol = "```" },
            Token{ .alphanumerical = "sh" },
            Token{ .space = "\n" },
            Token{ .alphanumerical = "echo" },
            Token{ .space = " " },
            Token{ .alphanumerical = "hello" },
            Token{ .space = " " },
            Token{ .alphanumerical = "world" },
            Token{ .symbol = ";" },
            Token{ .space = "\n" },
            Token{ .symbol = "```" },
        },
    );
}

fn expectEqualTokens(token_list: std.ArrayList(Token), expected_tokens: []const Token) !void {
    const received_tokens = token_list.items;
    std.testing.expectEqualDeep(expected_tokens, received_tokens) catch |err| {
        std.debug.print("—" ** 80 ++ "\n", .{});
        var i: usize = 0;
        const len = @max(received_tokens.len, expected_tokens.len);
        while (i < len) : (i += 1) {
            const received = if (i < received_tokens.len) received_tokens[i].debugInfo() else "none";
            const expected = if (i < expected_tokens.len) expected_tokens[i].debugInfo() else "none";
            if (!std.mem.eql(u8, received, expected)) {
                std.debug.print("received[{any}]: {s}\n", .{ i, received });
                std.debug.print("expected[{any}]: {s}\n", .{ i, expected });
            }
        }
        std.debug.print("—" ** 80 ++ "\n", .{});
        std.debug.print("{any}\n", .{err});
        std.debug.print("—" ** 80 ++ "\n", .{});
        return err;
    };
}
