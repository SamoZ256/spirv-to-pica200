const std = @import("std");
const testing = std.testing;
const translator = @import("translator.zig");

// TODO: fix memory leaks
fn testShader(comptime shader_name: []const u8) !void {
    // Read SPIR-V and PICA200 assembly expected output
    const data = @embedFile("test_shaders/" ++ shader_name ++ ".spv");
    const expected = @embedFile("test_shaders/" ++ shader_name ++ ".v.pica");

    // Convert
    const spv_len = data.len / @sizeOf(u32) * @sizeOf(u8);
    const spv = @as([*]const u32, @ptrCast(@alignCast(data.ptr)))[0..spv_len];

    // Translate
    var translatr = translator.Translator.init(testing.allocator, spv);
    errdefer translatr.deinit();

    var output = std.ArrayList(u8).init(testing.allocator);
    errdefer output.deinit();

    try translatr.translate(output.writer());

    // Compare
    try testing.expectEqualStrings(expected, output.items);
}

test "simple shader" {
    try testShader("simple");
}
