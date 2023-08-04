const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    comptime {
        const current_zig = builtin.zig_version;
        const min_zig = std.SemanticVersion.parse("0.11.0") catch unreachable; // Merge pull request #16446 from MasterQ32/buildsystem_rename_orgy
        if (current_zig.order(min_zig) == .lt) {
            @compileError(std.fmt.comptimePrint("Your Zig version v{} does not meet the minimum build requirement of v{}", .{ current_zig, min_zig }));
        }
    }

    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{ .name = "zig-worktree", .root_source_file = std.build.FileSource.relative("src/main.zig"), .target = target, .optimize = optimize });
    addPaths(exe);
    exe.linkSystemLibrary("git2");
    exe.linkLibC();
    //exe.install();
    b.installArtifact(exe);

    const exe_tests = b.addTest(.{ .name = "zig-worktree", .root_source_file = std.build.FileSource.relative("src/main.zig"), .target = target, .optimize = optimize });

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}

// add `include` and `lib` paths
fn addPaths(exe: *std.build.CompileStep) void {
    switch (builtin.target.os.tag) {
        .windows => {
            exe.addIncludePath(std.build.LazyPath.relative("./deps/include"));
            exe.addLibraryPath(std.build.LazyPath.relative("./deps/lib"));
        },
        .freebsd, .openbsd, .netbsd, .linux => {
            // use system paths
        },
        .macos => {
            exe.addIncludePath(.{ .cwd_relative = "/opt/homebrew/include" });
            exe.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/lib" });
        },
        else => {
            @compileError("Platform is not supported!");
        },
    }
}
