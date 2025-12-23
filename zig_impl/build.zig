const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // This creates a "module", which represents a collection of source files alongside
    // some compilation options, such as optimization mode and linked system libraries.
    // Every executable or library we compile will be based on one or more modules.
    const lib_mod = b.createModule(.{
        // `root_source_file` is the Zig "entry point" of the module. If a module
        // only contains e.g. external object files, you can make this `null`.
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Now, we will create a static library based on the module we created above.
    // This creates a `std.Build.Step.Compile`, which is the build step responsible
    // for actually invoking the compiler.
    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "callbacks",
        .root_module = lib_mod,
    });

    lib.bundle_compiler_rt = true;
    lib.bundle_ubsan_rt = true;
    lib.linkLibC();

    // Deps for zzplot
    const zzplot_dep = b.dependency("zzplot", .{});
    const nanovg_dep = b.dependency("nanovg", .{ .target = target, .optimize = optimize });

    const zzplot = zzplot_dep.module("ZZPlot");
    lib.root_module.addImport("zzplot", zzplot);
    for (zzplot.include_dirs.items) |dir| {
        lib.addIncludePath(dir.path);
    }

    lib.addCSourceFile(.{ .file = nanovg_dep.path("lib/gl2/src/glad.c"), .flags = &.{} });
    // exe.addCSourceFile(.{ .file = nanovg_dep.path("src/fontstash.c"), .flags = &.{ "-DFONS_NO_STDIO", "-fno-stack-protector" } });

    lib.addIncludePath(nanovg_dep.path("lib/gl2/include"));
    lib.linkSystemLibrary("glfw");
    lib.linkSystemLibrary("GL");
    lib.linkSystemLibrary("X11");

    // Deps for zzplot

    const libusb_dep = b.dependency("libusb", .{});
    const libusb = libusb_dep.builder.addTranslateC(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = .{
            .dependency = .{ .dependency = libusb_dep, .sub_path = "libusb/libusb.h" },
        },
    });
    const libusb_mod = libusb.addModule("libusb");
    lib.root_module.addImport("libusb", libusb_mod);
    const libusb_obj = libusb_dep.artifact("usb");

    const nanopb_generator = b.addSystemCommand(&.{"python3"});
    nanopb_generator.addArgs(&.{
        "./nanopb/generator/nanopb_generator.py",
        "--strip-path",
        "-L#include \"%s\"",
        "src/proto/messages.proto",
    });

    const nanopb_translate = b.addTranslateC(.{
        .root_source_file = b.path("src/proto/nanopb.h"),
        .target = target,
        .optimize = optimize,
    });
    nanopb_translate.step.dependOn(&nanopb_generator.step);
    const nanopb = nanopb_translate.addModule("nanopb");
    nanopb.addCSourceFiles(.{
        .root = b.path("src/proto"),
        .files = &.{ "pb_common.c", "pb_decode.c", "pb_encode.c", "messages.pb.c" },
        .flags = &.{},
    });
    nanopb.addIncludePath(b.path("src/proto/"));

    lib.root_module.addImport("nanopb", nanopb);

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    b.installArtifact(libusb_obj);
    b.installArtifact(lib);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const lib_unit_tests = b.addTest(.{
        .root_module = lib_mod,
    });

    lib_unit_tests.linkSystemLibrary("glfw");
    lib_unit_tests.linkSystemLibrary("GL");
    lib_unit_tests.linkSystemLibrary("X11");
    lib_unit_tests.linkSystemLibrary("libudev");
    lib_unit_tests.linkLibrary(libusb_obj);
    lib_unit_tests.root_module.addImport("libusb", libusb_mod);

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const usb_mod = b.addModule("usb", .{
        .root_source_file = b.path("src/usb.zig"),
    });

    const usb_tests = b.addTest(.{
        .root_source_file = b.path("src/test_usb.zig"),
        .target = target,
        .optimize = optimize,
    });

    usb_tests.root_module.addImport("libusb", libusb_mod);
    usb_tests.root_module.addImport("usb", usb_mod);
    usb_tests.linkSystemLibrary("usb-1.0");

    const run_usb_tests = b.addRunArtifact(usb_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    // _ = run_lib_unit_tests;
    test_step.dependOn(&run_usb_tests.step);
}
