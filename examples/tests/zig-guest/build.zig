const std = @import("std");

pub fn build(b: *std.Build) !void {
    const optimize = b.standardOptimizeOption(.{});

    const wasm = b.addExecutable(.{
        .name = "zig-guest",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = b.resolveTargetQuery(.{
                .cpu_arch = .wasm32,
                .os_tag = .wasi,
            }),
            .optimize = optimize,
        }),
    });

    // Add C bindings
    const binding_root = "src/bindings";
    wasm.addCSourceFile(.{
        .file = b.path(binding_root ++ "/types_test.c"),
        .flags = &.{},
    });
    wasm.addObjectFile(b.path(binding_root ++ "/types_test_component_type.o"));
    wasm.root_module.addIncludePath(b.path(binding_root));
    wasm.root_module.link_libc = true;

    // Export memory for component model
    wasm.entry = .disabled;
    wasm.rdynamic = true;

    b.installArtifact(wasm);
}
