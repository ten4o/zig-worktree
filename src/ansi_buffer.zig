const std = @import("std");
const ansi = @import("ansi_codes.zig");
const CSI = ansi.CSI;

pub fn AnsiBuffer(comptime size: usize) type {
    return struct {
        const Self = @This();
        pos: usize,
        buf: [size]u8,

        pub fn init() Self {
            return Self{
                .pos = 0,
                .buf = undefined,
            };
        }
        pub fn toSlice(self: *Self) []u8 {
            return self.buf[0..self.pos];
        }
        pub fn reset(self: *Self) void {
            self.pos = 0;
        }
        pub fn csi(self: *Self) void {
            self.buf[self.pos] = CSI[0];
            self.buf[self.pos + 1] = CSI[1];
            self.pos += 2;
        }
        pub fn fill(self: *Self, char: []const u8, fsize: usize) void {
            var i: usize = self.pos;
            const limit = fsize * char.len + self.pos;
            while (i < limit) : (i += char.len) {
                std.mem.copy(u8, self.buf[i..], char);
            }
            self.pos += limit;
        }
        pub fn concat(self: *Self, s: []const u8) void {
            std.mem.copy(u8, self.buf[self.pos..], s);
            self.pos += s.len;
        }
        pub fn concatChar(self: *Self, char: u8) void {
            self.buf[self.pos] = char;
            self.pos += 1;
        }
        pub fn concatU16(self: *Self, num: u16) void {
            var i: usize = 0;
            var stack: [8]u8 = undefined;
            var locnum = num;
            while (locnum > 0) : (locnum /= 10) {
                stack[i] = @intCast(locnum % 10);
                i += 1;
            }
            var j: usize = self.pos;
            while (i > 0) : (i -= 1) {
                self.buf[j] = '0' + stack[i - 1];
                j += 1;
            }
            self.pos = j;
        }
        pub fn cursorPos(self: *Self, top: u16, left: u16) void {
            // CSI v ; h H	- Cursor Position
            self.csi();
            self.concatU16(top);
            self.concatChar(';');
            self.concatU16(left);
            self.concatChar('H');
        }
        fn hideCursor(self: *Self) void {
            self.concat(CSI ++ "?25l");
        }
        pub fn setColor(self: *Self, color: u8) void {
            self.concat(CSI ++ "38;5;");
            self.concatU16(color);
            self.concatChar('m');
        }
        pub fn setBackground(self: *Self, color: u8) void {
            self.concat(CSI ++ "48;5;");
            self.concatU16(color);
            self.concatChar('m');
        }
        pub fn setDefault(self: *Self) void {
            self.csi();
            self.concat("0m");
        }
    };
}
