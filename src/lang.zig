const std = @import("std");
const ir = @import("ir.zig");

const bom = "\xEF\xBB\xBF";

const Word = enum {
    ai_nike,
    nike,
    buhio,
    punike,
    norukasu,
    mikaze,
};

const Token = struct {
    kind: Word,
    lexeme: []const u8,
    span: Span,
};

pub const Span = struct {
    start: usize,
    end: usize,
    word_index: usize,
};

pub const DiagnosticKind = enum {
    invalid_utf8,
    unknown_word,
    odd_word_count,
    invalid_pair,
    unmatched_loop_start,
    unmatched_loop_end,
};

pub const Diagnostic = struct {
    kind: DiagnosticKind,
    primary: Span,
    got_first: ?[]const u8 = null,
    got_second: ?[]const u8 = null,

    pub fn render(self: Diagnostic, writer: anytype) !void {
        switch (self.kind) {
            .invalid_utf8 => {
                try writer.writeAll("nike parse error: source must be valid UTF-8\n");
            },
            .unknown_word => {
                try writer.print(
                    "nike parse error at word {d}: unknown word `{s}`; expected one of AIニケ / ニケ / ブヒ夫 / ぷにけ / ノルカス / ミカゼ\n",
                    .{ self.primary.word_index + 1, self.got_first.? },
                );
            },
            .odd_word_count => {
                try writer.print(
                    "nike parse error at word {d}: instructions are two-word phrases, but `{s}` is dangling without a partner\n",
                    .{ self.primary.word_index + 1, self.got_first.? },
                );
            },
            .invalid_pair => {
                try writer.print(
                    "nike parse error at words {d}-{d}: invalid instruction pair `{s} {s}`\n",
                    .{ self.primary.word_index + 1, self.primary.word_index + 2, self.got_first.?, self.got_second.? },
                );
            },
            .unmatched_loop_start => {
                try writer.print(
                    "nike parse error at words {d}-{d}: loop start has no matching end\n",
                    .{ self.primary.word_index + 1, self.primary.word_index + 2 },
                );
            },
            .unmatched_loop_end => {
                try writer.print(
                    "nike parse error at words {d}-{d}: loop end has no matching start\n",
                    .{ self.primary.word_index + 1, self.primary.word_index + 2 },
                );
            },
        }

        if (self.kind != .invalid_utf8) {
            try writer.print("  byte range: {d}..{d}\n", .{ self.primary.start, self.primary.end });
        }
    }
};

pub const CompileResult = union(enum) {
    program: ir.Program,
    err: Diagnostic,
};

pub fn compileSource(allocator: std.mem.Allocator, original_source: []const u8) !CompileResult {
    if (!std.unicode.utf8ValidateSlice(original_source)) {
        return .{
            .err = .{
                .kind = .invalid_utf8,
                .primary = .{ .start = 0, .end = @min(original_source.len, 1), .word_index = 0 },
            },
        };
    }

    const source = if (std.mem.startsWith(u8, original_source, bom))
        original_source[bom.len..]
    else
        original_source;

    var tokens = std.ArrayList(Token).init(allocator);
    defer tokens.deinit();

    var cursor: usize = 0;
    var word_index: usize = 0;
    while (cursor < source.len) {
        while (cursor < source.len and std.ascii.isWhitespace(source[cursor])) : (cursor += 1) {}
        if (cursor >= source.len) break;

        const start = cursor;
        while (cursor < source.len and !std.ascii.isWhitespace(source[cursor])) : (cursor += 1) {}
        const lexeme = source[start..cursor];

        const kind = identifyWord(lexeme) orelse {
            return .{
                .err = .{
                    .kind = .unknown_word,
                    .primary = .{ .start = start, .end = cursor, .word_index = word_index },
                    .got_first = lexeme,
                },
            };
        };

        try tokens.append(.{
            .kind = kind,
            .lexeme = lexeme,
            .span = .{ .start = start, .end = cursor, .word_index = word_index },
        });
        word_index += 1;
    }

    if (tokens.items.len % 2 != 0) {
        const dangling = tokens.items[tokens.items.len - 1];
        return .{
            .err = .{
                .kind = .odd_word_count,
                .primary = dangling.span,
                .got_first = dangling.lexeme,
            },
        };
    }

    var instructions = std.ArrayList(ir.Instruction).init(allocator);
    defer instructions.deinit();

    var loop_stack = std.ArrayList(Span).init(allocator);
    defer loop_stack.deinit();

    var token_index: usize = 0;
    while (token_index < tokens.items.len) : (token_index += 2) {
        const left = tokens.items[token_index];
        const right = tokens.items[token_index + 1];
        const pair_span = Span{
            .start = left.span.start,
            .end = right.span.end,
            .word_index = left.span.word_index,
        };

        const instruction = mapPair(left.kind, right.kind) orelse {
            return .{
                .err = .{
                    .kind = .invalid_pair,
                    .primary = pair_span,
                    .got_first = left.lexeme,
                    .got_second = right.lexeme,
                },
            };
        };

        switch (instruction) {
            .loop_start => try loop_stack.append(pair_span),
            .loop_end => {
                if (loop_stack.items.len == 0) {
                    return .{
                        .err = .{
                            .kind = .unmatched_loop_end,
                            .primary = pair_span,
                        },
                    };
                }
                _ = loop_stack.pop();
            },
            else => {},
        }

        try instructions.append(instruction);
    }

    if (loop_stack.items.len != 0) {
        return .{
            .err = .{
                .kind = .unmatched_loop_start,
                .primary = loop_stack.items[loop_stack.items.len - 1],
            },
        };
    }

    return .{
        .program = .{
            .allocator = allocator,
            .instructions = try instructions.toOwnedSlice(),
        },
    };
}

pub fn writeSpec(writer: anytype) !void {
    try writer.writeAll(
        "NIKE language v1\n" ++
            "- source must be valid UTF-8\n" ++
            "- whitespace is only a separator\n" ++
            "- every instruction is exactly two words\n" ++
            "- comments are not supported in v1\n" ++
            "- cells are 8-bit and wrap on overflow/underflow\n" ++
            "- tape grows to the right as needed\n" ++
            "- moving left from cell 0 is a runtime error\n" ++
            "- input EOF writes 0 into the current cell\n" ++
            "\n" ++
            "Instruction map:\n" ++
            "  AIニケ ニケ => >\n" ++
            "  ニケ AIニケ => <\n" ++
            "  ブヒ夫 ぷにけ => +\n" ++
            "  ぷにけ ブヒ夫 => -\n" ++
            "  ノルカス ミカゼ => .\n" ++
            "  ミカゼ ノルカス => ,\n" ++
            "  AIニケ ブヒ夫 => [\n" ++
            "  ブヒ夫 AIニケ => ]\n",
    );
}

fn identifyWord(word: []const u8) ?Word {
    if (std.mem.eql(u8, word, "AIニケ")) return .ai_nike;
    if (std.mem.eql(u8, word, "ニケ")) return .nike;
    if (std.mem.eql(u8, word, "ブヒ夫")) return .buhio;
    if (std.mem.eql(u8, word, "ぷにけ")) return .punike;
    if (std.mem.eql(u8, word, "ノルカス")) return .norukasu;
    if (std.mem.eql(u8, word, "ミカゼ")) return .mikaze;
    return null;
}

fn mapPair(left: Word, right: Word) ?ir.Instruction {
    return switch (left) {
        .ai_nike => switch (right) {
            .nike => .move_right,
            .buhio => .loop_start,
            else => null,
        },
        .nike => switch (right) {
            .ai_nike => .move_left,
            else => null,
        },
        .buhio => switch (right) {
            .punike => .increment,
            .ai_nike => .loop_end,
            else => null,
        },
        .punike => switch (right) {
            .buhio => .decrement,
            else => null,
        },
        .norukasu => switch (right) {
            .mikaze => .output,
            else => null,
        },
        .mikaze => switch (right) {
            .norukasu => .input,
            else => null,
        },
    };
}

test "compile valid source into IR" {
    const testing = std.testing;
    const result = try compileSource(testing.allocator, "AIニケ ニケ ブヒ夫 ぷにけ ノルカス ミカゼ");

    switch (result) {
        .program => |program| {
            defer program.deinit();
            try testing.expectEqual(@as(usize, 3), program.instructions.len);
            try testing.expectEqual(ir.Instruction.move_right, program.instructions[0]);
            try testing.expectEqual(ir.Instruction.increment, program.instructions[1]);
            try testing.expectEqual(ir.Instruction.output, program.instructions[2]);
        },
        .err => |diagnostic| {
            _ = diagnostic;
            return error.ExpectedProgram;
        },
    }
}

test "reject invalid word" {
    const testing = std.testing;
    const result = try compileSource(testing.allocator, "AIニケ ほげ");

    switch (result) {
        .program => |program| {
            defer program.deinit();
            return error.ExpectedDiagnostic;
        },
        .err => |diagnostic| try testing.expectEqual(DiagnosticKind.unknown_word, diagnostic.kind),
    }
}

test "reject odd word count" {
    const testing = std.testing;
    const result = try compileSource(testing.allocator, "AIニケ ニケ ブヒ夫");

    switch (result) {
        .program => |program| {
            defer program.deinit();
            return error.ExpectedDiagnostic;
        },
        .err => |diagnostic| try testing.expectEqual(DiagnosticKind.odd_word_count, diagnostic.kind),
    }
}

test "reject unmatched loop end" {
    const testing = std.testing;
    const result = try compileSource(testing.allocator, "ブヒ夫 AIニケ");

    switch (result) {
        .program => |program| {
            defer program.deinit();
            return error.ExpectedDiagnostic;
        },
        .err => |diagnostic| try testing.expectEqual(DiagnosticKind.unmatched_loop_end, diagnostic.kind),
    }
}

