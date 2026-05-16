const std = @import("std");
const builtin = @import("builtin");
const lang = @import("lang.zig");
const c_backend = @import("c_backend.zig");
const runner = @import("runner.zig");

const max_source_bytes = 8 * 1024 * 1024;

const CompileOptions = struct {
    input_path: []const u8,
    output_path: ?[]const u8 = null,
    emit_c_path: ?[]const u8 = null,
    zig_path: []const u8 = "zig",
};

pub fn main() !void {
    if (builtin.os.tag == .windows) {
        _ = std.os.windows.kernel32.SetConsoleOutputCP(65001);
    }

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const exit_code = runCli(allocator) catch |err| {
        const stderr = std.io.getStdErr().writer();
        try stderr.print("nike internal error: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };

    if (exit_code != 0) {
        std.process.exit(exit_code);
    }
}

fn runCli(allocator: std.mem.Allocator) !u8 {
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len <= 1) {
        try printUsage(stdout);
        return 0;
    }

    const command = args[1];
    if (std.mem.eql(u8, command, "help") or std.mem.eql(u8, command, "--help") or std.mem.eql(u8, command, "-h")) {
        try printUsage(stdout);
        return 0;
    }
    if (std.mem.eql(u8, command, "spec")) {
        try lang.writeSpec(stdout);
        return 0;
    }
    if (std.mem.eql(u8, command, "compile")) {
        const options = parseCompileArgs(args[2..]) catch |err| {
            try stderr.print("nike cli error: {s}\n\n", .{@errorName(err)});
            try printUsage(stderr);
            return 1;
        };
        return try handleCompile(allocator, stderr, options);
    }
    if (std.mem.eql(u8, command, "run")) {
        const input_path = parseRunArgs(args[2..]) catch |err| {
            try stderr.print("nike cli error: {s}\n\n", .{@errorName(err)});
            try printUsage(stderr);
            return 1;
        };
        return try handleRun(allocator, stderr, input_path);
    }

    try stderr.print("nike cli error: unknown command `{s}`\n\n", .{command});
    try printUsage(stderr);
    return 1;
}

fn handleCompile(allocator: std.mem.Allocator, stderr: anytype, options: CompileOptions) !u8 {
    const source = try readFile(allocator, options.input_path);
    defer allocator.free(source);

    const parsed = try lang.compileSource(allocator, source);
    switch (parsed) {
        .err => |diagnostic| {
            try diagnostic.render(stderr);
            return 1;
        },
        .program => |program| {
            defer program.deinit();

            const c_source = try c_backend.emitSource(allocator, program.instructions);
            defer allocator.free(c_source);

            if (options.emit_c_path) |emit_c_path| {
                try writeFile(emit_c_path, c_source);
            }

            if (options.output_path) |output_path| {
                runner.compileCToNative(allocator, options.zig_path, c_source, output_path) catch |err| {
                    switch (err) {
                        runner.RunnerError.MissingZigCompiler => {
                            try stderr.print(
                                "nike compile error: could not find Zig compiler `{s}`; pass --zig <path> or install zig\n",
                                .{options.zig_path},
                            );
                        },
                        runner.RunnerError.CompilerFailed => {
                            try stderr.writeAll("nike compile error: zig cc failed\n");
                        },
                        else => try stderr.print("nike compile error: {s}\n", .{@errorName(err)}),
                    }
                    return 1;
                };
            }

            return 0;
        },
    }
}

fn handleRun(allocator: std.mem.Allocator, stderr: anytype, input_path: []const u8) !u8 {
    const source = try readFile(allocator, input_path);
    defer allocator.free(source);

    const parsed = try lang.compileSource(allocator, source);
    switch (parsed) {
        .err => |diagnostic| {
            try diagnostic.render(stderr);
            return 1;
        },
        .program => |program| {
            defer program.deinit();

            runner.execute(
                allocator,
                program.instructions,
                std.io.getStdIn().reader(),
                std.io.getStdOut().writer(),
            ) catch |err| {
                switch (err) {
                    runner.RunnerError.PointerUnderflow => {
                        try stderr.writeAll("nike runtime error: pointer moved left of zero\n");
                    },
                    runner.RunnerError.InvalidProgram => {
                        try stderr.writeAll("nike runtime error: internal jump table mismatch\n");
                    },
                    else => try stderr.print("nike runtime error: {s}\n", .{@errorName(err)}),
                }
                return 1;
            };
            return 0;
        },
    }
}

fn parseCompileArgs(args: []const [:0]u8) !CompileOptions {
    var input_path: ?[]const u8 = null;
    var output_path: ?[]const u8 = null;
    var emit_c_path: ?[]const u8 = null;
    var zig_path: []const u8 = "zig";

    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const arg = args[index];

        if (std.mem.eql(u8, arg, "-o")) {
            index += 1;
            if (index >= args.len) return error.MissingOutputPath;
            output_path = args[index];
            continue;
        }
        if (std.mem.eql(u8, arg, "--emit-c")) {
            index += 1;
            if (index >= args.len) return error.MissingEmitCPath;
            emit_c_path = args[index];
            continue;
        }
        if (std.mem.eql(u8, arg, "--zig")) {
            index += 1;
            if (index >= args.len) return error.MissingZigPath;
            zig_path = args[index];
            continue;
        }
        if (std.mem.startsWith(u8, arg, "-")) {
            return error.UnknownOption;
        }
        if (input_path == null) {
            input_path = arg;
            continue;
        }
        return error.UnexpectedArgument;
    }

    if (input_path == null) return error.MissingInputPath;
    if (output_path == null and emit_c_path == null) return error.MissingCompileTarget;

    return .{
        .input_path = input_path.?,
        .output_path = output_path,
        .emit_c_path = emit_c_path,
        .zig_path = zig_path,
    };
}

fn parseRunArgs(args: []const [:0]u8) ![]const u8 {
    if (args.len != 1) return error.ExpectedSingleInputPath;
    return args[0];
}

fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    if (std.fs.path.isAbsolute(path)) {
        const file = try std.fs.openFileAbsolute(path, .{});
        defer file.close();
        return try file.readToEndAlloc(allocator, max_source_bytes);
    }
    return try std.fs.cwd().readFileAlloc(allocator, path, max_source_bytes);
}

fn writeFile(path: []const u8, data: []const u8) !void {
    if (std.fs.path.isAbsolute(path)) {
        const file = try std.fs.createFileAbsolute(path, .{ .truncate = true });
        defer file.close();
        try file.writeAll(data);
        return;
    }

    const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(data);
}

fn printUsage(writer: anytype) !void {
    try writer.writeAll(
        \\NIKE language CLI
        \\
        \\Commands:
        \\  nike spec
        \\      Print the NIKE language specification.
        \\
        \\  nike run <input.nike>
        \\      Parse and run a NIKE source file with the built-in interpreter.
        \\
        \\  nike compile <input.nike> -o <output.exe> [--emit-c <output.c>] [--zig <path-to-zig>]
        \\      Compile NIKE source to a native executable through generated C.
        \\      --emit-c can be used by itself when you only want the generated C source.
        \\
    );
}

