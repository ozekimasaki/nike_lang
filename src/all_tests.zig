const std = @import("std");
const lang = @import("lang.zig");
const runner = @import("runner.zig");
const c_backend = @import("c_backend.zig");

test "A program prints A through parser and interpreter" {
    const testing = std.testing;
    const source =
        \\ブヒ夫 ぷにけ ブヒ夫 ぷにけ ブヒ夫 ぷにけ ブヒ夫 ぷにけ
        \\ブヒ夫 ぷにけ ブヒ夫 ぷにけ ブヒ夫 ぷにけ ブヒ夫 ぷにけ
        \\AIニケ ブヒ夫
        \\AIニケ ニケ
        \\ブヒ夫 ぷにけ ブヒ夫 ぷにけ ブヒ夫 ぷにけ ブヒ夫 ぷにけ
        \\ブヒ夫 ぷにけ ブヒ夫 ぷにけ ブヒ夫 ぷにけ ブヒ夫 ぷにけ
        \\ニケ AIニケ
        \\ぷにけ ブヒ夫
        \\ブヒ夫 AIニケ
        \\AIニケ ニケ
        \\ブヒ夫 ぷにけ
        \\ノルカス ミカゼ
    ;

    const parsed = try lang.compileSource(testing.allocator, source);
    switch (parsed) {
        .err => |diagnostic| {
            _ = diagnostic;
            return error.ExpectedProgram;
        },
        .program => |program| {
            defer program.deinit();

            var output = std.ArrayList(u8).init(testing.allocator);
            defer output.deinit();

            var empty_input = std.io.fixedBufferStream("");
            try runner.execute(testing.allocator, program.instructions, empty_input.reader(), output.writer());
            try testing.expectEqualStrings("A", output.items);

            const c_source = try c_backend.emitSource(testing.allocator, program.instructions);
            defer testing.allocator.free(c_source);
            try testing.expect(std.mem.indexOf(u8, c_source, "putchar") != null);
        },
    }
}
