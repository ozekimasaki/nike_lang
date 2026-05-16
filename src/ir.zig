pub const Instruction = enum(u8) {
    move_right,
    move_left,
    increment,
    decrement,
    output,
    input,
    loop_start,
    loop_end,
};

pub const Program = struct {
    allocator: @import("std").mem.Allocator,
    instructions: []Instruction,

    pub fn deinit(self: Program) void {
        self.allocator.free(self.instructions);
    }
};

