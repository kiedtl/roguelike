const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const termbox_sources = [_][]const u8{
        "tb/src/input.c",
        "tb/src/memstream.c",
        "tb/src/ringbuffer.c",
        "tb/src/termbox.c",
        "tb/src/term.c",
        "tb/src/utf8.c",
    };

    const termbox_cflags = [_][]const u8{
        "-std=c99",
        "-Wpedantic",
        "-Wall",
        "-Werror",
        "-g",
        "-I./tb/src",
        "-D_POSIX_C_SOURCE=200809L",
        "-D_XOPEN_SOURCE",
    };

    const exe = b.addExecutable("rl", "src/main.zig");
    for (termbox_sources) |termbox_source|
        exe.addCSourceFile(termbox_source, &termbox_cflags);
    exe.linkLibC();
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
