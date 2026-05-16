const std = @import("std");
const ir = @import("ir.zig");

pub const RunnerError = error{
    InvalidProgram,
    PointerUnderflow,
    MissingZigCompiler,
    CompilerFailed,
};

pub fn execute(
    allocator: std.mem.Allocator,
    instructions: []const ir.Instruction,
    reader: anytype,
    writer: anytype,
) !void {
    const jumps = try buildJumpTable(allocator, instructions);
    defer allocator.free(jumps);

    var tape = std.ArrayList(u8).init(allocator);
    defer tape.deinit();
    try tape.appendNTimes(0, 1024);

    var pointer: usize = 0;
    var ip: usize = 0;
    while (ip < instructions.len) {
        switch (instructions[ip]) {
            .move_right => {
                pointer += 1;
                if (pointer >= tape.items.len) {
                    try tape.appendNTimes(0, tape.items.len);
                }
                ip += 1;
            },
            .move_left => {
                if (pointer == 0) return RunnerError.PointerUnderflow;
                pointer -= 1;
                ip += 1;
            },
            .increment => {
                tape.items[pointer] +%= 1;
                ip += 1;
            },
            .decrement => {
                tape.items[pointer] -%= 1;
                ip += 1;
            },
            .output => {
                try writer.writeByte(tape.items[pointer]);
                ip += 1;
            },
            .input => {
                tape.items[pointer] = reader.readByte() catch |err| switch (err) {
                    error.EndOfStream => 0,
                    else => return err,
                };
                ip += 1;
            },
            .loop_start => {
                if (tape.items[pointer] == 0) {
                    ip = jumps[ip] + 1;
                } else {
                    ip += 1;
                }
            },
            .loop_end => {
                if (tape.items[pointer] != 0) {
                    ip = jumps[ip];
                } else {
                    ip += 1;
                }
            },
        }
    }
}

pub fn compileCToNative(
    allocator: std.mem.Allocator,
    zig_executable: []const u8,
    c_source: []const u8,
    output_path: []const u8,
) !void {
    var child = std.process.Child.init(&.{
        zig_executable,
        "cc",
        "-x",
        "c",
        "-",
        "-O2",
        "-o",
        output_path,
    }, allocator);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    child.spawn() catch |err| switch (err) {
        error.FileNotFound => return RunnerError.MissingZigCompiler,
        else => return err,
    };

    {
        const stdin = child.stdin.?;
        try stdin.writer().writeAll(c_source);
        stdin.close();
        child.stdin = null;
    }

    const term = try child.wait();
    switch (term) {
        .Exited => |code| {
            if (code != 0) return RunnerError.CompilerFailed;
        },
        else => return RunnerError.CompilerFailed,
    }
}

fn buildJumpTable(allocator: std.mem.Allocator, instructions: []const ir.Instruction) ![]usize {
    var jumps = try allocator.alloc(usize, instructions.len);
    errdefer allocator.free(jumps);

    var stack = std.ArrayList(usize).init(allocator);
    defer stack.deinit();

    for (instructions, 0..) |instruction, index| {
        jumps[index] = index;
        switch (instruction) {
            .loop_start => try stack.append(index),
            .loop_end => {
                if (stack.items.len == 0) return RunnerError.InvalidProgram;
                const start = stack.pop().?;
                jumps[start] = index;
                jumps[index] = start;
            },
            else => {},
        }
    }

    if (stack.items.len != 0) return RunnerError.InvalidProgram;
    return jumps;
}

test "execute simple program" {
    const testing = std.testing;
    var output = std.ArrayList(u8).init(testing.allocator);
    defer output.deinit();

    var empty_input = std.io.fixedBufferStream("");
    try execute(testing.allocator, &.{
        .increment, .increment, .increment, .increment, .increment,
        .increment, .increment, .increment, .increment, .increment,
        .increment, .increment, .increment, .increment, .increment,
        .increment, .increment, .increment, .increment, .increment,
        .increment, .increment, .increment, .increment, .increment,
        .increment, .increment, .increment, .increment, .increment,
        .increment, .increment, .increment, .increment, .increment,
        .increment, .increment, .increment, .increment, .increment,
        .increment, .increment, .increment, .increment, .increment,
        .increment, .increment, .increment, .increment, .increment,
        .increment, .increment, .increment, .increment, .increment,
        .increment, .increment, .increment, .increment, .increment,
        .increment, .increment, .increment, .increment, .increment,
        .output,
    }, empty_input.reader(), output.writer());

    try testing.expectEqualStrings("A", output.items);
}

