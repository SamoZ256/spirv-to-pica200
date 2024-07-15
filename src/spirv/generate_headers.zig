const std = @import("std");
const json = @import("json");

pub fn main() !void {
    // Allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // File
    const file = try std.fs.cwd().createFile("src/spirv/headers.zig", .{});
    defer file.close();
    var writer = file.writer();

    // SPIRV spec
    const spirv_spec_data = @embedFile("spirv.json");

    const spirv_spec_tree = try json.parse(spirv_spec_data, allocator);
    defer spirv_spec_tree.deinit(allocator);

    const spv_tree = spirv_spec_tree.get("spv");
    const enums_tree = spv_tree.get("enum");

    for (enums_tree.array().items()) |enum_tree| {
        const name = enum_tree.get("Name").string();
        const ty = enum_tree.get("Type").string();
        try writer.print("pub const {s} = enum(u32) {{\n", .{name});
        const values_tree = enum_tree.get("Values").object();
        for (values_tree.keys()) |key| {
            const value = values_tree.get(key).integer();
            try writer.print("    {s} = @as(u32, ", .{key});
            // TODO: check if this is correct
            if (std.mem.eql(u8, ty, "Bit")) {
                try writer.print("1 << ", .{});
            }
            try writer.print("{}),\n", .{value});
        }
        try writer.print("}};\n\n", .{});
    }

    // Instruction info
    try writer.print("pub const InstructionInfo = struct {{\n    has_result_type: bool,\n    has_result: bool,\n}};\n\n", .{});

    // SPIRV grammar
    const spirv_grammar_data = @embedFile("spirv.core.grammar.json");

    const spirv_grammar_tree = try json.parse(spirv_grammar_data, allocator);
    defer spirv_grammar_tree.deinit(allocator);

    const instructions_tree = spirv_grammar_tree.get("instructions");

    try writer.print("pub fn getInstructionInfo(op: Op) InstructionInfo {{\n    return switch (op) {{\n", .{});
    for (instructions_tree.array().items()) |instruction_tree| {
        const opname = instruction_tree.get("opname").string();
        const operands_tree = instruction_tree.object().getOrNull("operands");
        var has_result_type = false;
        var has_result = false;
        if (operands_tree) |operands| {
            for (operands.array().items()) |operand_tree| {
                const kind = operand_tree.get("kind").string();
                if (std.mem.eql(u8, kind, "IdResultType")) {
                    has_result_type = true;
                } else if (std.mem.eql(u8, kind, "IdResult")) {
                    has_result = true;
                }
            }
        }
        try writer.print("        {s} => .{{ .has_result_type = {}, .has_result = {} }},\n", .{opname, has_result_type, has_result});
    }
    try writer.print("    }};\n}}\n", .{});

    // TODO
    //try writer.flush();
}
