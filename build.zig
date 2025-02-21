const std = @import("std");
const Build = std.Build;

pub fn build(b: *Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const optimize = b.standardOptimizeOption(.{});

    var release_buf: [64]u8 = undefined;
    const slice = b.build_root.handle
        .readFile("RELEASE", &release_buf) catch @panic("Couldn't read RELEASE");
    const release = std.mem.trim(u8, slice, "\n");

    const dist: []const u8 = blk: {
        var ret: u8 = undefined;
        const output = b.runAllowFail(
            &[_][]const u8{ "git", "-C", b.build_root.path.?, "rev-parse", "HEAD" },
            &ret,
            .Inherit,
        ) catch break :blk "UNKNOWN";
        break :blk output[0..7];
    };

    const options = b.addOptions();
    options.addOption([]const u8, "release", release);
    options.addOption([]const u8, "dist", dist);

    const opt_tun_gif = b.option(bool, "tunneler-gif", "Link GIFLIB and use to export a GIF of the tunneler mapgen") orelse false;
    options.addOption(bool, "tunneler_gif", opt_tun_gif);

    const opt_use_sdl = b.option(bool, "use-sdl", "Build a graphical tiles version of Oathbreaker") orelse false;
    options.addOption(bool, "use_sdl", opt_use_sdl);

    const opt_build_fabedit = b.option(bool, "build-fabedit", "Build fabedit (dev utility)") orelse false;
    options.addOption(bool, "build_fabedit", opt_build_fabedit);

    const is_windows = target.result.os.tag == .windows;

    if (opt_build_fabedit) {
        const fabedit = b.addExecutable(.{
            .name = "rl_fabedit",
            .root_source_file = b.path("src/fabedit.zig"),
            .target = target,
            .optimize = optimize,
        });
        fabedit.linkLibC();
        fabedit.addIncludePath(b.path("third_party/janet/")); // janet.h
        fabedit.addIncludePath(b.path("third_party/microtar/src/"));
        fabedit.addIncludePath(Build.LazyPath{ .cwd_relative = "/usr/include/SDL2/" });
        fabedit.addCSourceFiles(.{
            .files = &[_][]const u8{
                "third_party/microtar/src/microtar.c", // FIXME: why is this needed
                "third_party/janet/janet.c",
            },
        });
        fabedit.linkSystemLibrary("SDL2");
        fabedit.linkSystemLibrary("z");
        fabedit.linkSystemLibrary("png");
        fabedit.root_module.addOptions("build_options", options);
        b.installArtifact(fabedit);
        const fabedit_run_cmd = b.addRunArtifact(fabedit);
        fabedit_run_cmd.step.dependOn(b.getInstallStep());
        const fabedit_run_step = b.step("run-fabedit", "Run fabedit");
        fabedit_run_step.dependOn(&fabedit_run_cmd.step);
        return;
    }

    const exe = b.addExecutable(.{
        .name = "rl",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibC();

    const rexpaint = b.addModule("rexpaint", .{
        .root_source_file = b.path("third_party/zig-rexpaint/lib.zig"),
    });
    //const libcoro = b.dependency("zigcoro", .{}).module("libcoro");

    exe.root_module.addImport("rexpaint", rexpaint);
    //exe.root_module.addImport("libcoro", libcoro);

    exe.addIncludePath(b.path("third_party/janet/")); // janet.h
    exe.addIncludePath(b.path("third_party/microtar/src/"));
    exe.addIncludePath(Build.LazyPath{ .cwd_relative = "/usr/include/SDL2/" });
    exe.addCSourceFiles(.{
        .files = &[_][]const u8{
            "third_party/microtar/src/microtar.c", // FIXME: why is this needed
            "third_party/janet/janet.c",
        },
    });

    if (opt_tun_gif) {
        exe.linkSystemLibrary("gif");
    }

    if (is_windows) {
        exe.addIncludePath(b.path("third_party/mingw/zlib/include/"));
        exe.addObjectFile(b.path("third_party/mingw/zlib/lib/libz.dll.a"));
        b.installBinFile("third_party/mingw/zlib/bin/zlib1.dll", "zlib1.dll");

        exe.addIncludePath(b.path("third_party/mingw/libpng/include/libpng16/"));
        exe.addObjectFile(b.path("third_party/mingw/libpng/lib/libpng.dll.a"));
        b.installBinFile("third_party/mingw/libpng/bin/libpng16-16.dll", "libpng16-16.dll");
    } else {
        exe.linkSystemLibrary("z");
        exe.linkSystemLibrary("png");
    }

    if (!opt_use_sdl) {
        const termbox_sources = [_][]const u8{
            "third_party/termbox/src/input.c",
            "third_party/termbox/src/memstream.c",
            "third_party/termbox/src/ringbuffer.c",
            "third_party/termbox/src/termbox.c",
            "third_party/termbox/src/term.c",
            "third_party/termbox/src/utf8.c",
        };

        const termbox_cflags = [_][]const u8{
            "-std=c99",
            "-Wpedantic",
            "-Wall",
            //"-Werror", // Disabled to keep clang from tantruming about unused
            //              function results in memstream.c
            "-g",
            "-I./third_party/termbox/src",
            "-D_POSIX_C_SOURCE=200809L",
            "-D_XOPEN_SOURCE",
            "-D_DARWIN_C_SOURCE", // Needed for macOS and SIGWINCH def
        };

        for (termbox_sources) |termbox_source|
            exe.addCSourceFile(.{ .file = b.path(termbox_source), .flags = &termbox_cflags });
    } else {
        if (is_windows) {
            exe.addIncludePath(b.path("third_party/mingw/SDL2/include/SDL2/"));
            exe.addObjectFile(b.path("third_party/mingw/SDL2/lib/libSDL2.dll.a"));
            b.installBinFile("third_party/mingw/SDL2/bin/SDL2.dll", "SDL2.dll");
        } else {
            exe.addIncludePath(Build.LazyPath{ .cwd_relative = "/usr/include/SDL2/" });
            exe.linkSystemLibrary("SDL2");
        }
    }

    exe.root_module.addOptions("build_options", options);

    b.installDirectory(.{
        .source_dir = b.path("data/"),
        .install_dir = .bin,
        .install_subdir = "data",
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run the roguelike");
    run_step.dependOn(&run_cmd.step);

    var tests = b.addTest(.{ .root_source_file = b.path("tests/tests.zig") });
    const tests_step = b.step("tests", "Run the various tests");
    //tests_step.dependOn(&exe.step);
    tests_step.dependOn(&tests.step);
}
