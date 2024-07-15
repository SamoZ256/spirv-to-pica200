const std = @import("std");
const testing = std.testing;
const translator = @import("translator.zig");

fn compileToPICA200(data: []const u8) ![]const u8 {
    const spv_len = data.len / @sizeOf(u32) * @sizeOf(u8);
    const spv = @as([*]const u32, @ptrCast(@alignCast(data.ptr)))[0..spv_len];

    const translatr = translator.Translator.init(spv);

    return translatr.translate();
}

test "simple shader" {
    const data = @embedFile("test_shaders/simple.spv");
    const pica200 = try compileToPICA200(data);
    try testing.expectEqual(pica200, "TODO: implement me!");
}
