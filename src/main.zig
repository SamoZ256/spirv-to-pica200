const std = @import("std");
const clap = @import("clap");
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
    var translatr = try translator.Translator.init(allocator, spv);
    errdefer translatr.deinit();

    var output = std.ArrayList(u8).init(allocator);
    errdefer output.deinit();

    try translatr.translate(output.writer());

    // Write to file
    var output_file = try std.fs.cwd().createFile(output_filename, .{});
    errdefer output_file.close();

    _ = try output_file.write(output.items);
}

fn compileShader(allocator: std.mem.Allocator, source_filename: []const u8, output_filename: []const u8, assembled_output_filename: []const u8, assembly: bool) !void {
    try compileShaderImpl(allocator, source_filename, output_filename);

    // Execute picasso assembler
    if (!assembly) {
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

fn compileTestShader(allocator: std.mem.Allocator, comptime test_name: []const u8, assembly: bool) !void {
    try compileShader(allocator, "src/test_shaders/" ++ test_name ++ ".spv", "src/test_shaders/" ++ test_name ++ ".v.pica", "src/test_shaders/" ++ test_name ++ ".shbin", assembly);
}

pub fn main() !void {
    // Allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    errdefer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const params = comptime clap.parseParamsComptime(
        \\-h, --help             Display this help and exit.
        \\-o, --output <str>     The output file.
        \\-S, --assembly         Output assembly instead of shader binary.
        \\-t, --test-shaders             Compile test shaders.
        \\<str>
        \\
    );

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
        .allocator = gpa.allocator(),
    }) catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };
    errdefer res.deinit();

    if (res.args.help != 0) {
        return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});
    }

    const assembly = (res.args.assembly != 0);
    if (res.args.@"test-shaders" != 0) {
        try compileTestShader(allocator, "simple", assembly);
        try compileTestShader(allocator, "math", assembly);
        try compileTestShader(allocator, "control_flow", assembly);
        try compileTestShader(allocator, "arrays", assembly);
        try compileTestShader(allocator, "std", assembly);
        try compileTestShader(allocator, "matrices", assembly);
        try compileTestShader(allocator, "functions", assembly);
    } else {
        var output1_filename = res.args.output.?;
        var output2_filename = res.args.output.?;
        if (assembly) {
            output2_filename = "";
        } else {
            output1_filename = ".temp/temp.v.pica";

            // Ensure the temo directory exists
            std.fs.cwd().makeDir(".temp") catch |e| {
                switch (e) {
                    error.PathAlreadyExists => {},
                    else => return e,
                }
            };
        }
        try compileShader(allocator, res.positionals[0], output1_filename, output2_filename, assembly);

        if (res.args.assembly == 0) {
            // Delete the temporary file
            try std.fs.cwd().deleteFile(".temp/temp.v.pica");
        }
    }
}
