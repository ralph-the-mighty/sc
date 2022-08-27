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
    program.mov_eax_32(encode_immediate_int(num));
    program.pop_rbp();
    program.ret();

    return program;
}

pub fn const_char_program(char: u8) win.VirtualAllocError!Program {
    var program: Program = Program{ .bytes = undefined, .counter = 0 };
    try program.init();
    program.push_rbp();
    program.mov_rbp_rsp();
    program.mov_eax_32(encode_immediate_char(char));
    program.pop_rbp();
    program.ret();

    return program;
}

pub fn const_bool_program(b: bool) win.VirtualAllocError!Program {
    var program: Program = Program{ .bytes = undefined, .counter = 0 };
    try program.init();
    program.push_rbp();
    program.mov_rbp_rsp();
    program.mov_eax_32(encode_immediate_bool(b));
    program.pop_rbp();
    program.ret();

    return program;
}
// types
const MAX_FIXNUM = 0x3fff_ffff;
const FIXNUM_MASK = 0x0000_0003;
const FIXNUM_TAG = 0;

pub fn is_int(word: u32) bool {
    return (word & @as(u32, FIXNUM_MASK)) == @as(u32, FIXNUM_TAG);
}

pub fn encode_immediate_int(word: u32) u32 {
    std.debug.assert(word <= @as(u32, MAX_FIXNUM));
    return (word << 2) | @as(u32, FIXNUM_TAG);
}

pub fn decode_immediate_int(word: u32) u32 {
    std.debug.assert(is_int(word));
    return word >> 2;
}

pub fn I(word: u32) u32 {
    return encode_immediate_int(word);
}

const MAX_CHAR = 0x0000_007f;
const CHAR_MASK = 0x0000_00ff;
const CHAR_TAG = 0xf;

pub fn is_char(word: u32) bool {
    return (word & @as(u32, CHAR_MASK)) == @as(u32, CHAR_TAG);
}

pub fn encode_immediate_char(char: u8) u32 {
    std.debug.assert(char <= @as(u8, MAX_CHAR));
    return (@as(u32, char) << 8) | @as(u32, CHAR_TAG);
}

pub fn decode_immediate_char(word: u32) u8 {
    std.debug.assert(is_char(word));
    return @truncate(u8, word >> 8);
}

pub fn C(char: u8) u32 {
    return encode_immediate_char(char);
}

const MAX_BOOL = 0x0000_0001;
const BOOL_MASK = 0x0000_007f;
const BOOL_TAG = 0x1f;

pub fn is_bool(word: u32) bool {
    return (word & @as(u32, BOOL_MASK)) == @as(u32, BOOL_TAG);
}

pub fn encode_immediate_bool(b: bool) u32 {
    return (@as(u32, @boolToInt(b)) << 7) | @as(u32, BOOL_TAG);
}

pub fn decode_immediate_bool(word: u32) bool {
    std.debug.assert(is_bool(word));
    return word >> 7 == 1;
}

pub fn B(b: bool) u32 {
    return encode_immediate_bool(b);
}

pub fn print(word: u32) void {
    if (is_bool(word)) {
        std.debug.print("'{c}'\n", .{decode_immediate_bool(word)});
    } else if (is_int(word)) {
        std.debug.print("{}\n", .{decode_immediate_int(word)});
    } else if (is_bool(word)) {
        if (decode_immediate_bool(word)) {
            std.debug.print("true\n", .{});
        } else {
            std.debug.print("false\n", .{});
        }
    } else {
        std.debug.print("unrecognized type: {b}\n", .{word});
    }
}

pub fn main() anyerror!void {
    var program = try const_int_program(42);
    defer program.deinit();
    print(program.run());
}

test "basic function" {
    var program: Program = Program{ .bytes = undefined, .counter = 0 };
    try program.init();
    defer program.deinit();
    program.push_rbp();
    program.mov_rbp_rsp();
    program.mov_eax_32(encode_immediate_int(42));
    program.pop_rbp();
    program.ret();

    try std.testing.expectEqual(decode_immediate_int(program.run()), @intCast(u32, 42));
}

test "test mov_eax" {
    var i: usize = 0;
    while (i < MAX_FIXNUM) : (i += 12345) {
        var program = try const_int_program(@intCast(u32, i));
        defer program.deinit();
        try std.testing.expectEqual(decode_immediate_int(program.run()), @intCast(u32, i));
    }
}

test "immediate int representation" {
    var ints = [_]u32{ 0, 1, MAX_FIXNUM };
    for (ints) |num| {
        try std.testing.expectEqual(decode_immediate_int(encode_immediate_int(num)), num);
    }
}

test "const int program" {
    var program = try const_int_program(42);
    defer program.deinit();
    try std.testing.expectEqual(program.run(), I(42));
}

test "basic char tests" {
    var char: u8 = 0;
    while (char <= MAX_CHAR) : (char += 1) {
        try std.testing.expectEqual(decode_immediate_char(encode_immediate_char(char)), char);
    }
}

test "const char program" {
    var program = try const_char_program('j');
    defer program.deinit();
    try std.testing.expectEqual(program.run(), C('j'));
}

test "basic bool test" {
    try std.testing.expectEqual(decode_immediate_bool(encode_immediate_bool(true)), true);
    try std.testing.expectEqual(decode_immediate_bool(encode_immediate_bool(false)), false);
}

test "const bool program" {
    var program = try const_bool_program(true);
    defer program.deinit();
    try std.testing.expectEqual(program.run(), B(true));

    var program2 = try const_bool_program(false);
    defer program2.deinit();
    try std.testing.expectEqual(program2.run(), B(false));
}
