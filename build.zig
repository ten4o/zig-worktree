const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.build.Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("zig-worktree", "src/main.zig");
    addPaths(exe);
    exe.linkSystemLibrary("git2");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.linkLibC();
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_tests = b.addTest("src/main.zig");
    exe_tests.setTarget(target);
    exe_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}

// add `include` and `lib` paths
fn addPaths(exe: *std.build.LibExeObjStep) void {
    switch (builtin.target.os.tag) {
        .windows => {
            exe.addIncludePath("./deps/include");
            exe.addLibraryPath(thisDir() ++ "/deps/lib");
        },
        .freebsd, .openbsd, .netbsd, .linux => {
        },
        .macos => {
            exe.addIncludePath("/opt/homebrew/include");
            exe.addLibraryPath("/opt/homebrew/lib");
        },
        else => {
            @compileError("Platform is not supported!");
        },
    }
}

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse ".";
}
