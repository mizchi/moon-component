const std = @import("std");

const c = @cImport({
    @cInclude("types_test.h");
});

// String type alias
const String = c.types_test_string_t;
const ListS32 = c.types_test_list_s32_t;
const ListS64 = c.types_test_list_s64_t;
const ListString = c.types_test_list_string_t;
const Color = c.exports_local_types_test_enums_color_t;
const Permissions = c.exports_local_types_test_flags_test_permissions_t;

// ============== Primitives ==============

export fn exports_local_types_test_primitives_echo_s32(val: i32) i32 {
    return val;
}

export fn exports_local_types_test_primitives_echo_s64(val: i64) i64 {
    return val;
}

export fn exports_local_types_test_primitives_echo_f32(val: f32) f32 {
    return val;
}

export fn exports_local_types_test_primitives_echo_f64(val: f64) f64 {
    return val;
}

export fn exports_local_types_test_primitives_echo_bool(val: bool) bool {
    return val;
}

export fn exports_local_types_test_primitives_echo_string(val: *String, ret: *String) void {
    // Copy string
    c.types_test_string_dup_n(ret, @ptrCast(val.ptr), val.len);
}

// ============== Enums ==============

export fn exports_local_types_test_enums_echo_color(color: Color) Color {
    return color;
}

export fn exports_local_types_test_enums_color_name(color: Color, ret: *String) void {
    const name = switch (color) {
        c.EXPORTS_LOCAL_TYPES_TEST_ENUMS_COLOR_RED => "red",
        c.EXPORTS_LOCAL_TYPES_TEST_ENUMS_COLOR_GREEN => "green",
        c.EXPORTS_LOCAL_TYPES_TEST_ENUMS_COLOR_BLUE => "blue",
        else => "unknown",
    };
    c.types_test_string_dup(ret, name.ptr);
}

// ============== Flags ==============

export fn exports_local_types_test_flags_test_echo_permissions(p: Permissions) Permissions {
    return p;
}

export fn exports_local_types_test_flags_test_has_read(p: Permissions) bool {
    return (p & c.EXPORTS_LOCAL_TYPES_TEST_FLAGS_TEST_PERMISSIONS_READ) != 0;
}

export fn exports_local_types_test_flags_test_has_write(p: Permissions) bool {
    return (p & c.EXPORTS_LOCAL_TYPES_TEST_FLAGS_TEST_PERMISSIONS_WRITE) != 0;
}

// ============== Containers ==============

export fn exports_local_types_test_containers_sum_list(vals: *ListS32) i32 {
    var sum: i32 = 0;
    for (0..vals.len) |i| {
        sum += vals.ptr[i];
    }
    return sum;
}

export fn exports_local_types_test_containers_echo_list_s64(vals: *ListS64, ret: *ListS64) void {
    // Allocate and copy using standard C malloc
    const byte_len = vals.len * @sizeOf(i64);
    const ptr: [*]i64 = @alignCast(@ptrCast(std.c.malloc(byte_len) orelse return));
    @memcpy(ptr[0..vals.len], vals.ptr[0..vals.len]);
    ret.ptr = ptr;
    ret.len = vals.len;
}

export fn exports_local_types_test_containers_count_list(vals: *ListString) i32 {
    return @intCast(vals.len);
}

export fn exports_local_types_test_containers_divide(a: i32, b: i32, ret: *i32, err: *String) bool {
    if (b == 0) {
        c.types_test_string_dup(err, "division by zero");
        return false; // return false -> is_err = true (wrapper negates)
    }
    ret.* = @divTrunc(a, b);
    return true; // return true -> is_err = false (wrapper negates)
}

// ============== Multi-params ==============

export fn exports_local_types_test_multi_params_add2(a: i32, b: i32) i32 {
    return a + b;
}

export fn exports_local_types_test_multi_params_add3(a: i32, b: i32, c_val: i32) i32 {
    return a + b + c_val;
}

export fn exports_local_types_test_multi_params_add4(a: i32, b: i32, c_val: i32, d: i32) i32 {
    return a + b + c_val + d;
}

export fn exports_local_types_test_multi_params_concat3(a: *String, b: *String, c_str: *String, ret: *String) void {
    const total_len = a.len + b.len + c_str.len;
    // Use standard C malloc for component model compatible allocation
    const ptr: [*]u8 = @ptrCast(std.c.malloc(total_len) orelse return);

    @memcpy(ptr[0..a.len], a.ptr[0..a.len]);
    @memcpy(ptr[a.len .. a.len + b.len], b.ptr[0..b.len]);
    @memcpy(ptr[a.len + b.len .. total_len], c_str.ptr[0..c_str.len]);

    ret.ptr = ptr;
    ret.len = total_len;
}

export fn exports_local_types_test_multi_params_mixed_params(n: i32, s: *String, b: bool, ret: *String) void {
    // Format: "n:s:b"
    var buf: [256]u8 = undefined;
    const bool_str = if (b) "true" else "false";

    // Simple integer to string
    var n_buf: [16]u8 = undefined;
    const n_str = intToStr(n, &n_buf);

    var pos: usize = 0;
    @memcpy(buf[pos .. pos + n_str.len], n_str);
    pos += n_str.len;
    buf[pos] = ':';
    pos += 1;
    @memcpy(buf[pos .. pos + s.len], s.ptr[0..s.len]);
    pos += s.len;
    buf[pos] = ':';
    pos += 1;
    @memcpy(buf[pos .. pos + bool_str.len], bool_str);
    pos += bool_str.len;

    c.types_test_string_dup_n(ret, &buf, pos);
}

fn intToStr(val: i32, buf: []u8) []const u8 {
    var v = val;
    var neg = false;
    if (v < 0) {
        neg = true;
        v = -v;
    }
    var i: usize = buf.len;
    if (v == 0) {
        i -= 1;
        buf[i] = '0';
    } else {
        while (v > 0) {
            i -= 1;
            buf[i] = @intCast(@as(u32, @intCast(@mod(v, 10))) + '0');
            v = @divTrunc(v, 10);
        }
    }
    if (neg) {
        i -= 1;
        buf[i] = '-';
    }
    return buf[i..];
}

// ============== Side-effects ==============

export fn exports_local_types_test_side_effects_no_return(_: *String) void {
    // Side effect only
}

export fn exports_local_types_test_side_effects_no_params_no_return() void {
    // No params, no return
}

// Required entry point (unused)
pub fn main() void {}
