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
        self.counter = 0;
    }

    pub fn emit_byte(self: *Program, byte: u8) void {
        self.bytes[self.counter] = byte;
        self.counter += 1;
    }

    pub fn emit_bytes(self: *Program, bytes: []const u8) void {
        for (bytes) |byte| {
            self.bytes[self.counter] = byte;
            self.counter += 1;
        }
    }

    pub fn emit_u64(self: *Program, word: u64) void {
        var i: usize = 0;
        while (i <= 56) : (i += 8) {
            const byte: u8 = @truncate(u8, word >> @truncate(u6, i));
            self.emit_byte(byte);
        }
    }
    pub fn push_rbp(self: *Program) void {
        self.emit_byte(0x55);
    }

    pub fn mov_rbp_rsp(self: *Program) void {
        self.emit_byte(0x48);
        self.emit_byte(0x89);
        self.emit_byte(0xe5);
    }

    pub fn mov_eax_64_imm(self: *Program, int: u64) void {
        self.emit_byte(0x48);
        self.emit_byte(0xb8);
        self.emit_u64(int);
    }

    //primatives
    pub fn emit_add1(self: *Program) void {
        self.emit_byte(0x48);
        self.emit_byte(0x83);
        self.emit_byte(0xc0);
        self.emit_byte(1 << 2);
    }
    pub fn emit_sub1(self: *Program) void {
        self.emit_byte(0x48);
        self.emit_byte(0x83);
        self.emit_byte(0xe8);
        self.emit_byte(1 << 2);
    }

    pub fn emit_integer_to_char(self: *Program) void {
        //shl rax, 0x6
        self.emit_byte(0x48);
        self.emit_byte(0xc1);
        self.emit_byte(0xe0);
        self.emit_byte(0x06);
        //or rax 0xf
        self.emit_byte(0x48);
        self.emit_byte(0x83);
        self.emit_byte(0xc8);
        self.emit_byte(0x0f);
    }

    pub fn emit_char_to_integer(self: *Program) void {
        //shr rax, 0x6
        self.emit_byte(0x48);
        self.emit_byte(0xc1);
        self.emit_byte(0xe8);
        self.emit_byte(0x06);
    }

    pub fn emit_is_zero(self: *Program) void {
        //cmp rax, 0
        self.emit_bytes(&.{ 0x48, 0x83, 0xf8, 0x00 });
        //mov rax, 0
        self.emit_bytes(&.{ 0x48, 0xc7, 0xc0, 0x00, 0x00, 0x00, 0x00 });
        //sete al
        self.emit_bytes(&.{ 0x0f, 0x94, 0xc0 });
        //shl rax, 0x7
        self.emit_bytes(&.{ 0x48, 0xc1, 0xe0, 0x07 });
        //or rax, 0x1f
        self.emit_bytes(&.{ 0x48, 0x83, 0xc8, 0x1f });
    }

    pub fn emit_is_null(self: *Program) void {
        //cmp rax, 0x2f; null value
        self.emit_bytes(&.{ 0x48, 0x83, 0xf8, 0x2f });
        //mov rax, 0x0
        self.emit_bytes(&.{ 0x48, 0xc7, 0xc0, 0x00, 0x00, 0x00, 0x00 });
        //sete al
        self.emit_bytes(&.{ 0x0f, 0x94, 0xc0 });
        //shl rax, 0x7
        self.emit_bytes(&.{ 0x48, 0xc1, 0xe0, 0x07 });
        //or rax, 0x1f
        self.emit_bytes(&.{ 0x48, 0x83, 0xc8, 0x1f });
    }

    pub fn pop_rbp(self: *Program) void {
        self.emit_byte(0x5d);
    }

    pub fn ret(self: *Program) void {
        self.emit_byte(0xc3);
    }

    pub fn print(self: *Program) void {
        var i: usize = 0;
        while (i < self.counter) : (i += 1) {
            std.debug.print("{x:0>2} ", .{self.bytes[i]});
        }
        std.debug.print("\n", .{});
    }

    pub fn emit_expr(self: *Program, expr: AstNode) void {
        switch (expr) {
            .Int => |value| {
                self.mov_eax_64_imm(encode_immediate_int(value));
            },
            .Bool => |value| {
                self.mov_eax_64_imm(encode_immediate_bool(value));
            },
            .Char => |value| {
                self.mov_eax_64_imm(encode_immediate_char(value));
            },
            .Null => {
                self.mov_eax_64_imm(NULL_VALUE);
            },
            .Unary => |value| {
                self.emit_expr(value.arg.*);
                if (std.mem.eql(u8, value.name, "add1")) {
                    self.emit_add1();
                } else if (std.mem.eql(u8, value.name, "sub1")) {
                    self.emit_sub1();
                } else if (std.mem.eql(u8, value.name, "char->integer")) {
                    self.emit_char_to_integer();
                } else if (std.mem.eql(u8, value.name, "integer->char")) {
                    self.emit_integer_to_char();
                } else if (std.mem.eql(u8, value.name, "null?")) {
                    self.emit_is_null();
                } else if (std.mem.eql(u8, value.name, "zero?")) {
                    self.emit_is_zero();
                } else {
                    unreachable;
                }
            },
        }
    }

    pub fn compile(self: *Program, expr: AstNode) void {
        //prologue
        self.push_rbp();
        self.mov_rbp_rsp();
        self.emit_expr(expr);
        //epilogue
        self.pop_rbp();
        self.ret();
    }

    pub fn recompile(self: *Program, expr: AstNode) void {
        std.mem.set(u8, self.bytes[0..self.counter], 0);
        self.counter = 0;
        self.compile(expr);
    }

    pub fn run(self: *Program) u64 {
        const fn_ptr = fn () callconv(.C) u64;
        const function: fn_ptr = @ptrCast(fn_ptr, self.bytes);
        return function();
    }
};

const AstType = enum { Int, Char, Bool, Null, Unary };

const AstNode = union(AstType) { Int: u64, Char: u8, Bool: bool, Null: u64, Unary: struct { name: []const u8, arg: *AstNode } };

// types
const MAX_FIXNUM = std.math.maxInt(u62);
const FIXNUM_MASK = 0x0000_0000_0000_0003;
const FIXNUM_TAG = 0;

pub fn is_int(word: u64) bool {
    return (word & @as(u64, FIXNUM_MASK)) == @as(u64, FIXNUM_TAG);
}

pub fn encode_immediate_int(word: u64) u64 {
    std.debug.assert(word <= @as(u64, MAX_FIXNUM));
    const x = (word << 2) | @as(u64, FIXNUM_TAG);
    return x;
}

pub fn decode_immediate_int(word: u64) u64 {
    std.debug.assert(is_int(word));
    return word >> 2;
}

pub fn I(word: u64) u64 {
    return encode_immediate_int(word);
}

const MAX_CHAR = 0x0000_0000_0000_007f;
const CHAR_MASK = 0x0000_0000_0000_00ff;
const CHAR_TAG = 0xf;

pub fn is_char(word: u64) bool {
    return (word & @as(u64, CHAR_MASK)) == @as(u64, CHAR_TAG);
}

pub fn encode_immediate_char(char: u8) u64 {
    std.debug.assert(char <= @as(u8, MAX_CHAR));
    return (@as(u64, char) << 8) | @as(u64, CHAR_TAG);
}

pub fn decode_immediate_char(word: u64) u8 {
    std.debug.assert(is_char(word));
    return @truncate(u8, word >> 8);
}

pub fn C(char: u8) u64 {
    return encode_immediate_char(char);
}

const BOOL_MASK = 0x0000_0000_0000_007f;
const BOOL_TAG = 0x1f;

pub fn is_bool(word: u64) bool {
    return (word & @as(u64, BOOL_MASK)) == @as(u64, BOOL_TAG);
}

pub fn encode_immediate_bool(b: bool) u64 {
    return (@as(u64, @boolToInt(b)) << 7) | @as(u64, BOOL_TAG);
}

pub fn decode_immediate_bool(word: u64) bool {
    std.debug.assert(is_bool(word));
    return word >> 7 == 1;
}

pub fn B(b: bool) u64 {
    return encode_immediate_bool(b);
}

const NULL_VALUE = 0x2f;

pub fn is_null(word: u64) bool {
    return word == @as(u64, NULL_VALUE);
}

pub fn ast_null() AstNode {
    return AstNode{ .Null = NULL_VALUE };
}

pub fn print(word: u64) void {
    if (is_char(word)) {
        std.debug.print("'{c}'\n", .{decode_immediate_char(word)});
    } else if (is_int(word)) {
        std.debug.print("{}\n", .{decode_immediate_int(word)});
    } else if (is_bool(word)) {
        if (decode_immediate_bool(word)) {
            std.debug.print("true\n", .{});
        } else {
            std.debug.print("false\n", .{});
        }
    } else if (is_null(word)) {
        std.debug.print("(nil)\n", .{});
    } else {
        std.debug.print("unrecognized type: {b}\n", .{word});
    }
}

pub fn main() anyerror!void {
    var n = AstNode{ .Char = 'a' };
    var m = AstNode{ .Unary = .{ .name = "char->integer", .arg = &n } };
    var o = AstNode{ .Unary = .{ .name = "add1", .arg = &m } };
    var p = AstNode{ .Unary = .{ .name = "integer->char", .arg = &o } };
    var program = Program{ .bytes = undefined, .counter = 0 };
    try program.init();
    defer program.deinit();

    program.compile(p);
    program.print();
    print(program.run());

    var q = ast_null();
    var r = AstNode{ .Unary = .{ .name = "null?", .arg = &q } };

    program.recompile(r);
    program.print();
    std.debug.print("{b}\n", .{program.run()});
    print(program.run());

    var a = AstNode{ .Int = 0 };
    var b = AstNode{ .Unary = .{ .name = "zero?", .arg = &a } };

    program.recompile(b);
    try std.testing.expectEqual(B(true), program.run());

    a = AstNode{ .Int = 2342 };
    program.recompile(b);
}

pub fn test_program(expr: AstNode, expected_value: u64) bool {
    var program: Program = Program{ .bytes = undefined, .counter = 0 };
    program.init() catch return false;
    defer program.deinit();

    program.compile(expr);
    return program.run() == expected_value;
}

test "basic function" {
    var program: Program = Program{ .bytes = undefined, .counter = 0 };
    try program.init();
    defer program.deinit();
    program.push_rbp();
    program.mov_rbp_rsp();
    program.mov_eax_64_imm(encode_immediate_int(42));
    program.pop_rbp();
    program.ret();

    try std.testing.expectEqual(decode_immediate_int(program.run()), @intCast(u64, 42));
}

test "test mov_eax" {
    var ints = [_]u64{ 0, 1, MAX_FIXNUM };
    for (ints) |num| {
        var program: Program = Program{ .bytes = undefined, .counter = 0 };
        defer program.deinit();
        try program.init();
        program.push_rbp();
        program.mov_rbp_rsp();
        program.mov_eax_64_imm(encode_immediate_int(num));
        program.pop_rbp();
        program.ret();

        try std.testing.expectEqual(decode_immediate_int(program.run()), @intCast(u64, num));
    }
}

test "immediate int representation" {
    var ints = [_]u64{ 0, 1, MAX_FIXNUM };
    for (ints) |num| {
        try std.testing.expectEqual(decode_immediate_int(encode_immediate_int(num)), num);
    }
}

test "basic char tests" {
    var char: u8 = 0;
    while (char <= MAX_CHAR) : (char += 1) {
        try std.testing.expectEqual(decode_immediate_char(encode_immediate_char(char)), char);
    }
}

test "const char program" {
    try std.testing.expect(test_program(AstNode{ .Char = 'j' }, C('j')));
}

test "basic bool test" {
    try std.testing.expectEqual(decode_immediate_bool(encode_immediate_bool(true)), true);
    try std.testing.expectEqual(decode_immediate_bool(encode_immediate_bool(false)), false);
}

test "const bool program" {
    try std.testing.expect(test_program(AstNode{ .Bool = true }, B(true)));
    try std.testing.expect(test_program(AstNode{ .Bool = false }, B(false)));
}

test "const int test" {
    try std.testing.expect(test_program(AstNode{ .Int = 42 }, I(42)));
}

test "null?" {
    var a = ast_null();
    var b = AstNode{ .Unary = .{ .name = "null?", .arg = &a } };

    try std.testing.expect(test_program(b, B(true)));

    a = AstNode{ .Int = 42 };
    try std.testing.expect(test_program(b, B(false)));
}

test "zero?" {
    var a = AstNode{ .Int = 0 };
    var b = AstNode{ .Unary = .{ .name = "zero?", .arg = &a } };

    try std.testing.expect(test_program(b, B(true)));

    a = AstNode{ .Int = 2342 };
    try std.testing.expect(test_program(b, B(false)));
}
