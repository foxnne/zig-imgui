const std = @import("std");
const builtin = @import("builtin");

const mach = @import("mach");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const use_freetype = b.option(bool, "use_freetype", "Use Freetype") orelse false;

    const mach_dep = b.dependency("mach", .{
        .target = target,
        .optimize = optimize,
    });

    const module = b.addModule("zig-imgui", .{
        .root_source_file = b.path("src/imgui.zig"),
        .imports = &.{
            .{ .name = "mach", .module = mach_dep.module("mach") },
        },
    });

    const lib = b.addStaticLibrary(.{
        .name = "imgui",
        .target = target,
        .optimize = optimize,
    });
    lib.linkLibC();

    const imgui_dep = b.dependency("imgui", .{});

    var files = std.ArrayList([]const u8).init(b.allocator);
    defer files.deinit();

    var flags = std.ArrayList([]const u8).init(b.allocator);
    defer flags.deinit();

    try files.appendSlice(&.{
        "src/cimgui.cpp",
        imgui_dep.builder.path("imgui.cpp").getPath(b),
        imgui_dep.builder.path("imgui_widgets.cpp").getPath(b),
        imgui_dep.builder.path("imgui_tables.cpp").getPath(b),
        imgui_dep.builder.path("imgui_draw.cpp").getPath(b),
        imgui_dep.builder.path("imgui_demo.cpp").getPath(b),
    });

    if (use_freetype) {
        try flags.append("-DIMGUI_ENABLE_FREETYPE");
        try files.append("imgui/misc/freetype/imgui_freetype.cpp");

        lib.linkLibrary(b.dependency("freetype", .{
            .target = target,
            .optimize = optimize,
        }).artifact("freetype"));
    }

    lib.addIncludePath(imgui_dep.path("."));

    for (files.items, 0..) |file, i| {
        if (i == 0) {
            lib.addCSourceFile(.{ .file = b.path(file), .flags = flags.items });
        } else {
            lib.addCSourceFile(.{ .file = .{ .cwd_relative = file }, .flags = flags.items });
        }
    }

    b.installArtifact(lib);

    // Example
    const exe = b.addExecutable(.{
        .name = "run",
        .root_source_file = b.path("examples/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("mach", mach_dep.module("mach"));
    exe.root_module.addImport("imgui", module);
    exe.linkLibrary(lib);

    const run_step = b.step("run", "Run the example");
    run_step.dependOn(&b.addRunArtifact(exe).step);

    b.installArtifact(exe);

    // Generator
    const generator_exe = b.addExecutable(.{
        .name = "mach-imgui-generator",
        .root_source_file = b.path("src/generate.zig"),
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(generator_exe);

    const generate_step = b.step("generate", "Generate the bindings");
    generate_step.dependOn(&b.addRunArtifact(generator_exe).step);
}
