const std = @import("std");
const translator = @import("translator.zig");

fn compileShaderImpl(allocator: std.mem.Allocator, source_filename: []const u8, output_filename: []const u8) !void {
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

fn compileShader(source_filename: []const u8, output_filename: []const u8, assembled_output_filename: []const u8) !void {
    // Allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    errdefer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try compileShaderImpl(allocator, source_filename, output_filename);

    // Assemble the output (if enabled)
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var assemble = false;
    for (1..args.len) |i| {
        if (std.mem.eql(u8, args[i], "--assemble")) {
            assemble = true;
        }
    }

    // Execute picasso assembler
    if (assemble) {
        const command = try std.fmt.allocPrint(allocator, "picasso {s} -o {s}", .{output_filename, assembled_output_filename});
        errdefer allocator.free(command);

        var child = std.process.Child.init(
            &[_][]const u8{
                "/bin/sh",
                "-c",
                command,
            },
            allocator,
        );
        //errdefer child.deinit();

        // Execute the command
        try child.spawn();

        // Wait for the child process to finish
        const result = try child.wait();
        std.debug.print("Assembler result: {}\n", .{result});
    }
}

pub fn main() !void {
    try compileShader("src/test_shaders/simple.spv", "src/test_shaders/simple.v.pica", "src/test_shaders/simple.shbin");
    try compileShader("src/test_shaders/math.spv", "src/test_shaders/math.v.pica", "src/test_shaders/math.shbin");
    try compileShader("src/test_shaders/control_flow.spv", "src/test_shaders/control_flow.v.pica", "src/test_shaders/control_flow.shbin");
}
