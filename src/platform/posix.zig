const std = @import("std");
const builtin = @import("builtin");

const constants = switch (builtin.target.os.tag) {
    .windows => unreachable,
    .freebsd, .openbsd, .netbsd, .linux => std.os.linux,
    .macos => std.c,
    else => {
        @compileError("Platform is not supported!");
    },
};
pub const TermAttr = constants.termios;

pub fn uncookStdout(handle: std.fs.File.Handle, saved_state: *TermAttr) !void {
    var attr = try std.os.tcgetattr(handle);
    saved_state.* = attr;
    attr.lflag &= ~@as(std.os.system.tcflag_t, constants.ECHO | constants.ICANON);

    attr.iflag &= ~@as(std.os.system.tcflag_t, constants.ICRNL);
    // Disable output processing. Common output processing includes prefixing
    // newline with a carriage return.
    attr.oflag &= ~@as(std.os.system.tcflag_t, constants.OPOST);

    // With these settings, the read syscall will immediately return when it
    // can't get any bytes. This allows poll to drive our loop.
    attr.cc[constants.V.TIME] = 0;
    attr.cc[constants.V.MIN] = 0;

    try std.os.tcsetattr(handle, .FLUSH, attr);
}

pub fn uncookStdin(handle: std.fs.File.Handle, saved_state: *TermAttr) !void {
    _ = handle;
    _ = saved_state;
}
pub fn restoreStdout(handle: std.fs.File.Handle, prev_state: TermAttr) !void {
    try std.os.tcsetattr(handle, .FLUSH, prev_state);
}
pub fn restoreStdin(handle: std.fs.File.Handle, prev_state: TermAttr) !void {
    _ = handle;
    _ = prev_state;
}
