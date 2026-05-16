const std = @import("std");
const ir = @import("ir.zig");

pub fn emitSource(allocator: std.mem.Allocator, instructions: []const ir.Instruction) ![]u8 {
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    const writer = buffer.writer();

    try writer.writeAll(
        \\#include <stdint.h>
        \\#include <stdio.h>
        \\#include <stdlib.h>
        \\#include <string.h>
        \\
        \\static void nike_oom(void) {
        \\    fputs("nike runtime error: out of memory\n", stderr);
        \\    exit(1);
        \\}
        \\
        \\static void nike_grow(uint8_t **tape, size_t *tape_len, size_t needed_index) {
        \\    if (needed_index < *tape_len) {
        \\        return;
        \\    }
        \\
        \\    size_t new_len = *tape_len;
        \\    while (needed_index >= new_len) {
        \\        new_len *= 2;
        \\    }
        \\
        \\    uint8_t *grown = (uint8_t *)realloc(*tape, new_len);
        \\    if (!grown) {
        \\        nike_oom();
        \\    }
        \\
        \\    memset(grown + *tape_len, 0, new_len - *tape_len);
        \\    *tape = grown;
        \\    *tape_len = new_len;
        \\}
        \\
        \\int main(void) {
        \\    size_t tape_len = 1024;
        \\    size_t ptr = 0;
        \\    uint8_t *tape = (uint8_t *)calloc(tape_len, 1);
        \\    if (!tape) {
        \\        nike_oom();
        \\    }
        \\
    );

    var indent: usize = 1;
    for (instructions) |instruction| {
        switch (instruction) {
            .move_right => {
                try writeIndent(writer, indent);
                try writer.writeAll("ptr += 1;\n");
                try writeIndent(writer, indent);
                try writer.writeAll("nike_grow(&tape, &tape_len, ptr);\n");
            },
            .move_left => {
                try writeIndent(writer, indent);
                try writer.writeAll("if (ptr == 0) {\n");
                try writeIndent(writer, indent + 1);
                try writer.writeAll("fputs(\"nike runtime error: pointer moved left of zero\\n\", stderr);\n");
                try writeIndent(writer, indent + 1);
                try writer.writeAll("free(tape);\n");
                try writeIndent(writer, indent + 1);
                try writer.writeAll("return 1;\n");
                try writeIndent(writer, indent);
                try writer.writeAll("}\n");
                try writeIndent(writer, indent);
                try writer.writeAll("ptr -= 1;\n");
            },
            .increment => {
                try writeIndent(writer, indent);
                try writer.writeAll("tape[ptr] += 1;\n");
            },
            .decrement => {
                try writeIndent(writer, indent);
                try writer.writeAll("tape[ptr] -= 1;\n");
            },
            .output => {
                try writeIndent(writer, indent);
                try writer.writeAll("(void)putchar(tape[ptr]);\n");
            },
            .input => {
                try writeIndent(writer, indent);
                try writer.writeAll("{\n");
                try writeIndent(writer, indent + 1);
                try writer.writeAll("int nike_input = getchar();\n");
                try writeIndent(writer, indent + 1);
                try writer.writeAll("tape[ptr] = nike_input == EOF ? 0 : (uint8_t)nike_input;\n");
                try writeIndent(writer, indent);
                try writer.writeAll("}\n");
            },
            .loop_start => {
                try writeIndent(writer, indent);
                try writer.writeAll("while (tape[ptr] != 0) {\n");
                indent += 1;
            },
            .loop_end => {
                indent -= 1;
                try writeIndent(writer, indent);
                try writer.writeAll("}\n");
            },
        }
    }

    try writer.writeAll(
        \\    free(tape);
        \\    return 0;
        \\}
        \\
    );

    return try buffer.toOwnedSlice();
}

fn writeIndent(writer: anytype, level: usize) !void {
    var i: usize = 0;
    while (i < level) : (i += 1) {
        try writer.writeAll("    ");
    }
}

test "emit C source contains loop and runtime helpers" {
    const testing = std.testing;
    const source = try emitSource(testing.allocator, &.{
        .increment,
        .loop_start,
        .move_right,
        .loop_end,
    });
    defer testing.allocator.free(source);

    try testing.expect(std.mem.indexOf(u8, source, "while (tape[ptr] != 0)") != null);
    try testing.expect(std.mem.indexOf(u8, source, "nike_grow") != null);
}

