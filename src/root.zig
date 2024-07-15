const std = @import("std");
const testing = std.testing;

fn compileToPICA200(shader: []const u8) !void {
    std.debug.print("Shader: {any}\n", .{shader});

    return;
}

test "simple shader" {
    const shader = @embedFile("test_shaders/simple.spv");
    try compileToPICA200(shader);
}
