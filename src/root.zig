const std = @import("std");
const testing = std.testing;
const translator = @import("translator.zig");

// TODO: fix memory leaks
fn testShader(comptime shader_name: []const u8) !void {
    // HACK
    // Allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    errdefer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Read SPIR-V and PICA200 assembly expected output
    const data = @embedFile("test_shaders/" ++ shader_name ++ ".spv");
    const expected = @embedFile("test_shaders/" ++ shader_name ++ ".v.pica");

    // Convert
    const spv_len = data.len / @sizeOf(u32) * @sizeOf(u8);
    const spv = @as([*]const u32, @ptrCast(@alignCast(data.ptr)))[0..spv_len];

    // Translate
    // TODO: use testing.allocator
    var translatr = try translator.Translator.init(allocator, spv);
    errdefer translatr.deinit();

    // TODO: use testing.allocator
    var output = std.ArrayList(u8).init(allocator);
    errdefer output.deinit();

    try translatr.translate(output.writer());

    // Compare
    try testing.expectEqualStrings(expected, output.items);
}

test "simple" {
    try testShader("simple");
}

test "math" {
    try testShader("math");
}

test "control flow" {
    try testShader("control_flow");
}

test "arrays" {
    try testShader("arrays");
}

test "standard library" {
    try testShader("std");
}
