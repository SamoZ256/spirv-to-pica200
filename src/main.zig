const std = @import("std");
const translator = @import("translator.zig");

fn compileShader(source_filename: []const u8, output_filename: []const u8) !void {
    // Allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    errdefer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Read SPIR-V
    var source_file = try std.fs.cwd().openFile(source_filename, .{});
    errdefer source_file.close();

    const buffer = try source_file.readToEndAlloc(allocator, std.math.maxInt(usize));
    errdefer allocator.free(buffer);

    // Convert to []const u32
    const spv_len = buffer.len / @sizeOf(u32) * @sizeOf(u8);
    const spv = @as([*]const u32, @ptrCast(@alignCast(buffer.ptr)))[0..spv_len];

    // Translate to PICA200 assembly
    var translatr = translator.Translator.init(allocator, spv);
    errdefer translatr.deinit();

    var output = std.ArrayList(u8).init(allocator);
    errdefer output.deinit();

    try translatr.translate(output.writer());

    // Write to file
    // TODO: why does it want c_uint instead of .write_only?
    var output_file = try std.fs.cwd().createFile(output_filename, .{ .mode = 1 });
    errdefer output_file.close();

    _ = try output_file.write(output.items);
}

pub fn main() !void {
    try compileShader("src/test_shaders/simple.spv", "src/test_shaders/simple.v.pica");
    try compileShader("src/test_shaders/math.spv", "src/test_shaders/math.v.pica");
    try compileShader("src/test_shaders/control_flow.spv", "src/test_shaders/control_flow.v.pica");
}
