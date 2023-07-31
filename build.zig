const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "zig-worktree",
        .root_source_file = std.build.FileSource.relative("src/main.zig"),
        .target = target,
        .optimize = optimize
    });
    addPaths(exe);
    exe.linkSystemLibrary("git2");
    exe.linkLibC();
    //exe.install();
    b.installArtifact(exe);



    const exe_tests = b.addTest(.{
        .name = "zig-worktree",
        .root_source_file = std.build.FileSource.relative("src/main.zig"),
        .target = target,
        .optimize = optimize
    });

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}

// add `include` and `lib` paths
fn addPaths(exe: *std.build.CompileStep) void {
    switch (builtin.target.os.tag) {
        .windows => {
            exe.addIncludePath("./deps/include");
            exe.addLibraryPath(thisDir() ++ "/deps/lib");
        },
        .freebsd, .openbsd, .netbsd, .linux => {
            // use system paths
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
