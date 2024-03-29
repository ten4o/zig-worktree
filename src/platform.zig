const builtin = @import("builtin");

const platform = switch (builtin.target.os.tag) {
    .windows => @import("platform/windows.zig"),
    .freebsd, .openbsd, .netbsd, .linux, .macos => @import("platform/posix.zig"),
    else => {
        @compileError("Platform is not supported!");
    },
};

pub usingnamespace platform;
