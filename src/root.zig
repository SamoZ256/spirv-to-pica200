const std = @import("std");
const testing = std.testing;
const translator = @import("translator.zig");

fn compileToPICA200(data: []const u8) !void {
    const spv_len = data.len / @sizeOf(u32) * @sizeOf(u8);
    const spv = @as([*]const u32, @ptrCast(@alignCast(data.ptr)))[0..spv_len];

    var translatr = translator.Translator.init(spv);

    try translatr.translate(std.io.getStdOut().writer());
}

test "simple shader" {
    std.debug.print("Begin\n", .{});
    const data = @embedFile("test_shaders/simple.spv");
    try compileToPICA200(data);
}
