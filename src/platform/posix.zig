const std = @import("std");
const builtin = @import("builtin");

pub const constants = switch (builtin.target.os.tag) {
    .windows => unreachable,
    .linux => std.os.linux,
    .freebsd, .openbsd, .netbsd, .macos => std.c,
    else => {
        @compileError("Platform is not supported!");
    },
};

pub const TermAttr = constants.termios;

pub fn uncookStdout(handle: std.fs.File.Handle, saved_state: *TermAttr) !void {
    var attr = try std.posix.tcgetattr(handle);
    saved_state.* = attr;
    attr.lflag.ECHO = false;
    attr.lflag.ICANON = false;

    attr.iflag.ICRNL = false;

    // Disable output processing. Common output processing includes prefixing
    // newline with a carriage return.
    attr.oflag.OPOST = false;

    // With these settings, the read syscall will immediately return when it
    // can't get any bytes. This allows poll to drive our loop.
    attr.cc[@intFromEnum(std.c.V.TIME)] = 0;
    attr.cc[@intFromEnum(std.c.V.MIN)] = 0;

    try std.posix.tcsetattr(handle, .FLUSH, attr);
}

pub fn uncookStdin(handle: std.fs.File.Handle, saved_state: *TermAttr) !void {
    _ = handle;
    _ = saved_state;
}
pub fn restoreStdout(handle: std.fs.File.Handle, prev_state: TermAttr) !void {
    try std.posix.tcsetattr(handle, .FLUSH, prev_state);
}
pub fn restoreStdin(handle: std.fs.File.Handle, prev_state: TermAttr) !void {
    _ = handle;
    _ = prev_state;
}
