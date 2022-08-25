const std = @import("std");
const win = std.os.windows;

const Program = struct {
    bytes: [*]u8,
    counter: usize,

    pub fn init(self: *Program) win.VirtualAllocError!void {
        const memory: win.LPVOID = try win.VirtualAlloc(null, 4096, win.MEM_COMMIT | win.MEM_RESERVE, win.PAGE_EXECUTE_READWRITE);
        self.bytes = @ptrCast([*]u8, memory);
        self.counter = 0;
    }

    pub fn deinit(self: *Program) void {
        win.VirtualFree(self.bytes, 0, win.MEM_RELEASE);
    }

    pub fn emit_byte(self: *Program, byte: u8) void {
        self.bytes[self.counter] = byte;
        self.counter += 1;
    }

    pub fn emit_u32(self: *Program, word: u32) void {
        self.emit_byte(@truncate(u8, word >> 0) & @intCast(u8, 0xff));
        self.emit_byte(@truncate(u8, word >> 8) & @intCast(u8, 0xff));
        self.emit_byte(@truncate(u8, word >> 16) & @intCast(u8, 0xff));
        self.emit_byte(@truncate(u8, word >> 24) & @intCast(u8, 0xff));
    }

    pub fn push_rbp(self: *Program) void {
        self.emit_byte(0x55);
    }

    pub fn mov_rbp_rsp(self: *Program) void {
        self.emit_byte(0x48);
        self.emit_byte(0x89);
        self.emit_byte(0xe5);
    }

    pub fn mov_eax_0x2a(self: *Program) void {
        self.emit_byte(0xb8);
        self.emit_byte(0x2a);
        self.emit_byte(0);
        self.emit_byte(0);
        self.emit_byte(0);
    }

    pub fn mov_eax_32(self: *Program, int: u32) void {
        self.emit_byte(0xb8);
        self.emit_u32(int);
    }

    pub fn pop_rbp(self: *Program) void {
        self.emit_byte(0x5d);
    }

    pub fn ret(self: *Program) void {
        self.emit_byte(0xc3);
    }

    pub fn run(self: *Program) u32 {
        const fn_ptr = fn () callconv(.C) u32;
        const function: fn_ptr = @ptrCast(fn_ptr, self.bytes);
        return function();
    }
};

pub fn const_int_program(num: u32) win.VirtualAllocError!Program {
    var program: Program = Program{ .bytes = undefined, .counter = 0 };
    try program.init();
    program.push_rbp();
    program.mov_rbp_rsp();
    program.mov_eax_32(num);
    program.pop_rbp();
    program.ret();

    return program;
}

pub fn main() anyerror!void {
    // Note that info level log messages are by default printed only in Debug
    // and ReleaseSafe build modes.
    var program = try const_int_program(42);
    defer program.deinit();
    std.debug.print("{}\n", .{program.run()});
}

test "basic function" {
    var program: Program = Program{ .bytes = undefined, .counter = 0 };
    try program.init();
    defer program.deinit();
    program.push_rbp();
    program.mov_rbp_rsp();
    program.mov_eax_32(42);
    program.pop_rbp();
    program.ret();

    try std.testing.expectEqual(@intCast(u32, 42), program.run());
}

test "test mov_eax" {
    var i: usize = 0;
    while (i < 0xffff_ffff) : (i += 12345) {
        var program = try const_int_program(@intCast(u32, i));
        defer program.deinit();
        try std.testing.expectEqual(@intCast(u32, i), program.run());
    }
}
