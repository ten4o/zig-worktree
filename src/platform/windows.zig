const std = @import("std");

pub const TermAttr = struct {
    stdout: DWORD,
    stdin: DWORD,
};

pub extern "kernel32" fn SetConsoleMode(in_hConsoleHandle: HANDLE, in_lpMode: DWORD) callconv(WINAPI) BOOL;

const HANDLE = std.os.windows.HANDLE;
const DWORD = std.os.windows.DWORD;
const WINAPI = std.os.windows.WINAPI;
const BOOL = std.os.windows.BOOL;

const ENABLE_LINE_INPUT = 2;
const ENABLE_VIRTUAL_TERMINAL_INPUT = 0x0200;
const ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x0004;
const ENABLE_MOUSE_INPUT = 0x0010;
const ENABLE_WINDOW_INPUT = 0x0008;
const CP_UTF8 = 65001;

pub fn uncookStdout(handle: std.fs.File.Handle, saved_state: *TermAttr) !void {
    var mode: DWORD = undefined;
    var res = std.os.windows.kernel32.GetConsoleMode(handle, &mode);
    saved_state.*.stdout = mode;

    res = SetConsoleMode(handle, mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING);
    _ = std.os.windows.kernel32.SetConsoleOutputCP(CP_UTF8);
}
pub fn uncookStdin(handle: std.fs.File.Handle, saved_state: *TermAttr) !void {
    var mode: DWORD = undefined;
    var res = std.os.windows.kernel32.GetConsoleMode(handle, &mode);
    saved_state.*.stdin = mode;

    res = SetConsoleMode(handle, (mode | ENABLE_VIRTUAL_TERMINAL_INPUT) & ~@as(DWORD, ENABLE_LINE_INPUT));
}
pub fn restoreStdout(handle: std.fs.File.Handle, prev_state: TermAttr) !void {
    var res = SetConsoleMode(handle, prev_state.stdout);
    _ = res;
}
pub fn restoreStdin(handle: std.fs.File.Handle, prev_state: TermAttr) !void {
    var res = SetConsoleMode(handle, prev_state.stdin);
    _ = res;
}


