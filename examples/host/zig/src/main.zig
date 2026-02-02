const std = @import("std");

/// WebAssembly binary format parser for validation testing
/// This validates that generated wasm modules have correct export structure
/// without requiring a full wasm runtime.

const WasmError = error{
    InvalidMagic,
    InvalidVersion,
    InvalidSection,
    UnexpectedEnd,
    ExportNotFound,
};

const WASM_MAGIC = [_]u8{ 0x00, 0x61, 0x73, 0x6D };
const WASM_VERSION = [_]u8{ 0x01, 0x00, 0x00, 0x00 };

const SectionId = enum(u8) {
    custom = 0,
    type = 1,
    import = 2,
    function = 3,
    table = 4,
    memory = 5,
    global = 6,
    @"export" = 7,
    start = 8,
    element = 9,
    code = 10,
    data = 11,
    data_count = 12,
};

const ExportKind = enum(u8) {
    func = 0,
    table = 1,
    memory = 2,
    global = 3,
};

const Export = struct {
    name: []const u8,
    kind: ExportKind,
    index: u32,
};

const WasmModule = struct {
    data: []const u8,
    exports: std.ArrayListUnmanaged(Export),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, data: []const u8) !WasmModule {
        var module = WasmModule{
            .data = data,
            .exports = .{},
            .allocator = allocator,
        };

        try module.parse();
        return module;
    }

    pub fn deinit(self: *WasmModule) void {
        self.exports.deinit(self.allocator);
    }

    fn parse(self: *WasmModule) !void {
        var offset: usize = 0;

        // Check magic number
        if (self.data.len < 8) return WasmError.UnexpectedEnd;
        if (!std.mem.eql(u8, self.data[0..4], &WASM_MAGIC)) {
            return WasmError.InvalidMagic;
        }
        offset += 4;

        // Check version
        if (!std.mem.eql(u8, self.data[4..8], &WASM_VERSION)) {
            return WasmError.InvalidVersion;
        }
        offset += 4;

        // Parse sections
        while (offset < self.data.len) {
            const section_id = self.data[offset];
            offset += 1;

            const section_size = try readLEB128u32(self.data, &offset);
            const section_end = offset + section_size;

            if (section_id == @intFromEnum(SectionId.@"export")) {
                try self.parseExportSection(self.data[offset..section_end]);
            }

            offset = section_end;
        }
    }

    fn parseExportSection(self: *WasmModule, data: []const u8) !void {
        var offset: usize = 0;
        const count = try readLEB128u32(data, &offset);

        for (0..count) |_| {
            const name_len = try readLEB128u32(data, &offset);
            const name = data[offset .. offset + name_len];
            offset += name_len;

            const kind: ExportKind = @enumFromInt(data[offset]);
            offset += 1;

            const index = try readLEB128u32(data, &offset);

            try self.exports.append(self.allocator, .{
                .name = name,
                .kind = kind,
                .index = index,
            });
        }
    }

    pub fn hasExport(self: *const WasmModule, name: []const u8) bool {
        for (self.exports.items) |exp| {
            if (std.mem.eql(u8, exp.name, name)) {
                return true;
            }
        }
        return false;
    }

    pub fn getFunctionExports(self: *const WasmModule) std.ArrayListUnmanaged([]const u8) {
        var funcs: std.ArrayListUnmanaged([]const u8) = .{};
        for (self.exports.items) |exp| {
            if (exp.kind == .func) {
                funcs.append(self.allocator, exp.name) catch {};
            }
        }
        return funcs;
    }
};

fn readLEB128u32(data: []const u8, offset: *usize) !u32 {
    var result: u32 = 0;
    var shift: u5 = 0;

    while (true) {
        if (offset.* >= data.len) return WasmError.UnexpectedEnd;
        const byte = data[offset.*];
        offset.* += 1;

        result |= @as(u32, byte & 0x7F) << shift;
        if (byte & 0x80 == 0) break;
        shift += 7;
    }

    return result;
}

fn validateTypesTestModule(module: *const WasmModule) !void {
    std.debug.print("\n--- Validating types-test module exports ---\n", .{});

    // Expected exports from types-test
    const expected_exports = [_][]const u8{
        "memory",
        "cabi_realloc",
        "_start",
        // Primitives interface
        "local:types-test/primitives#echo-s32",
        "local:types-test/primitives#echo-s64",
        "local:types-test/primitives#echo-f32",
        "local:types-test/primitives#echo-f64",
        "local:types-test/primitives#echo-bool",
        "local:types-test/primitives#echo-string",
        // Enums interface
        "local:types-test/enums#echo-color",
        "local:types-test/enums#color-name",
        // Flags interface
        "local:types-test/flags-test#echo-permissions",
        "local:types-test/flags-test#has-read",
        "local:types-test/flags-test#has-write",
        // Multi-params interface
        "local:types-test/multi-params#add2",
        "local:types-test/multi-params#add3",
        "local:types-test/multi-params#add4",
        "local:types-test/multi-params#concat3",
        "local:types-test/multi-params#mixed-params",
        // Containers interface
        "local:types-test/containers#sum-list",
        "local:types-test/containers#divide",
        // Side-effects interface
        "local:types-test/side-effects#no-return",
        "local:types-test/side-effects#no-params-no-return",
    };

    var passed: usize = 0;
    var failed: usize = 0;

    for (expected_exports) |name| {
        if (module.hasExport(name)) {
            std.debug.print("  ✓ {s}\n", .{name});
            passed += 1;
        } else {
            std.debug.print("  ✗ {s} (not found)\n", .{name});
            failed += 1;
        }
    }

    std.debug.print("\nExport validation: {d} passed, {d} failed\n", .{ passed, failed });

    if (failed > 0) {
        return WasmError.ExportNotFound;
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const wasm_path = if (args.len > 1)
        args[1]
    else
        "../../tests/types-test/_build/wasm/release/build/src/src.wasm";

    std.debug.print("Loading wasm module: {s}\n", .{wasm_path});

    const file = std.fs.cwd().openFile(wasm_path, .{}) catch |err| {
        std.debug.print("Failed to open file: {}\n", .{err});
        return err;
    };
    defer file.close();

    const wasm_bytes = try file.readToEndAlloc(allocator, 10 * 1024 * 1024);
    defer allocator.free(wasm_bytes);

    var module = try WasmModule.init(allocator, wasm_bytes);
    defer module.deinit();

    std.debug.print("Wasm module parsed successfully!\n", .{});
    std.debug.print("Total exports: {d}\n", .{module.exports.items.len});

    // Validate expected exports
    try validateTypesTestModule(&module);

    std.debug.print("\nAll validation tests PASSED!\n", .{});
}

test "wasm module parsing" {
    const allocator = std.testing.allocator;

    // Minimal valid wasm module (just magic + version + empty type section)
    const minimal_wasm = [_]u8{
        0x00, 0x61, 0x73, 0x6D, // magic
        0x01, 0x00, 0x00, 0x00, // version
        0x01, 0x01, 0x00, // type section (id=1, size=1, count=0)
    };

    var module = try WasmModule.init(allocator, &minimal_wasm);
    defer module.deinit();

    try std.testing.expectEqual(@as(usize, 0), module.exports.items.len);
}

test "invalid magic number" {
    const allocator = std.testing.allocator;
    const bad_wasm = [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00 };

    const result = WasmModule.init(allocator, &bad_wasm);
    try std.testing.expectError(WasmError.InvalidMagic, result);
}
