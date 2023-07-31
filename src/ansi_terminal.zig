const std = @import("std");
const builtin = @import("builtin");
const allocator = std.heap.page_allocator;
const ansi = @import("ansi_codes.zig");
const platform = @import("platform.zig").platform;

const TermSize = struct {
    width: i32,
    height: i32,
};

pub const AnsiTerminal = struct {
    const Self = @This();
    size: TermSize,
    stdin: std.fs.File.Reader,
    stdout: std.fs.File.Writer,
    tty_state: platform.TermAttr,

    pub fn init() !Self {
        const stdin_file = std.io.getStdIn();
        const stdout_file = std.io.getStdOut();
        const stdout = stdout_file.writer();
        const stdin = stdin_file.reader();
        const tsize = try detectSize(stdout_file);

        var tty_state: platform.TermAttr = undefined;
        try platform.uncookStdout(stdout_file.handle, &tty_state);
        try platform.uncookStdin(stdin_file.handle, &tty_state);
        _ = try stdout.write(ansi.ENTER_SCREEN);

        //jconst colorterm = std.process.getEnvVarOwned(allocator, "COLORTERM") catch "n/a";
        //try stdout.print("{s}\n", .{colorterm});
        //const term = std.process.getEnvVarOwned(allocator, "TERM") catch "n/a";
        //try stdout.print("{s}\n", .{term});

        return Self{
            .size = tsize,
            .stdin = stdin,
            .stdout = stdout,
            .tty_state = tty_state,
        };
    }
    pub fn deinit(self: *Self) void {
        platform.restoreStdout(self.stdout.context.handle, self.tty_state) catch unreachable;
        platform.restoreStdin(self.stdin.context.handle, self.tty_state) catch unreachable;
        _ = self.stdout.write(ansi.EXIT_SCREEN) catch unreachable;
    }

    pub fn read(self: Self, buffer: []u8) !usize {
        var pready: usize = val: {
            if (builtin.target.os.tag == .windows) {
                break :val 1;
            } else {
                var pollfds = [_]std.os.pollfd{std.os.pollfd{ .fd = self.stdin.context.handle, .events = 1, .revents = 0 }};
                break :val try std.os.poll(&pollfds, -1);
            }
        };
        if (pready > 0) {
            return try self.stdin.read(buffer);
        }
        return 0;
    }
};

fn in(needle: u8, comptime slice: []const u8) bool {
    inline for (slice) |ch| {
        if (needle == ch) return true;
    }
    return false;
}

fn detectSize(stdout_file: std.fs.File) !TermSize {
    return switch (builtin.target.os.tag) {
        .windows => detectSizeWindows(stdout_file),
        else => detectSizePosix(stdout_file.handle),
    } catch {
        return detectSizeUgly();
    };
}

fn detectSizePosix(handle: std.os.fd_t) !TermSize {
    var size = std.mem.zeroes(platform.constants.winsize);
    const err = std.os.system.ioctl(handle, platform.constants.T.IOCGWINSZ, @intFromPtr(&size));
    if (std.os.errno(err) != .SUCCESS) {
        return std.os.unexpectedErrno(@enumFromInt(err));
    }
    return TermSize{
        .width = size.ws_col,
        .height = size.ws_row,
    };
}

fn detectSizeUgly() !TermSize {
    const argv = [_][]const u8{ "stty", "size" };
    var child_proc = std.ChildProcess.init(&argv, allocator);
    child_proc.stdout_behavior = std.ChildProcess.StdIo.Pipe;
    try child_proc.spawn();
    var child_stdout: [1024]u8 = undefined;
    var bread = try std.os.read(child_proc.stdout.?.handle, &child_stdout);

    var line = child_stdout[0..bread];
    while (line.len > 0 and in(line.ptr[line.len - 1], &[_]u8{ 10, 13 })) {
        line.len -= 1;
    }
    var tsize: TermSize = undefined;
    var iter = std.mem.split(u8, line, " ");
    var token_n: u8 = 0;
    while (iter.next()) |token| {
        if (token_n == 0) {
            tsize.height = std.fmt.parseInt(i32, token, 10) catch 24;
        } else {
            tsize.width = std.fmt.parseInt(i32, token, 10) catch 80;
        }
        token_n += 1;
    }
    _ = try child_proc.wait();
    return tsize;
}

fn detectSizeWindows(stdout_file: std.fs.File) !TermSize {
    var info: std.os.windows.CONSOLE_SCREEN_BUFFER_INFO = undefined;
    const res = std.os.windows.kernel32.GetConsoleScreenBufferInfo(stdout_file.handle, &info);
    if (res > 0) {
        return .{
            //.width = info.dwSize.X,
            //.height = info.dwSize.Y,
            .width = info.dwMaximumWindowSize.X,
            .height = info.dwMaximumWindowSize.Y,
        };
    }
    const err = std.os.windows.kernel32.GetLastError();
    const stdout = stdout_file.writer();
    try stdout.print("console buf info error {}\n", .{err});
    return error.AccessDenied;
}
