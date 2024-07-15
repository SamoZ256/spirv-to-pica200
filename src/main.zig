const std = @import("std");
const translator = @import("translator.zig");

pub fn main() !void {
    std.debug.print("Begin\n", .{});
    const data = @embedFile("test_shaders/simple.spv");

    const spv_len = data.len / @sizeOf(u32) * @sizeOf(u8);
    const spv = @as([*]const u32, @ptrCast(@alignCast(data.ptr)))[0..spv_len];

    var translatr = translator.Translator.init(spv);

    try translatr.translate(std.io.getStdOut().writer());
}
