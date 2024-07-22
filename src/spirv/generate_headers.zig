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
        const is_bit = std.mem.eql(u8, ty, "Bit");
        try writer.print("pub const {s} = enum(u32) {{\n", .{name});
        const values_tree = enum_tree.get("Values").object();

        // Store the previous value in case the next one is just an alias
        var previous_value: i64 = -1;
        for (values_tree.keys()) |key| {
            const value = values_tree.get(key).integer();
            if (value == previous_value) {
                continue;
            }
            previous_value = value;
            try writer.print("    {s} = @as(u32, ", .{key});
            // TODO: check if this is correct
            if (is_bit) {
                try writer.print("1 << ", .{});
            }
            try writer.print("{}),\n", .{value});
        }
        try writer.print("}};\n\n", .{});
    }

    // Instruction info
    try writer.print("pub const OperandType = enum {{\n    result_type_id,\n    result_id,\n    id_ref,\n    other,\n}};\n\n", .{});
    try writer.print("pub const InstructionInfo = struct {{\n    operands: []const OperandType,\n}};\n\n", .{});

    // SPIRV grammar
    const spirv_grammar_data = @embedFile("spirv.core.grammar.json");

    const spirv_grammar_tree = try json.parse(spirv_grammar_data, allocator);
    defer spirv_grammar_tree.deinit(allocator);

    const instructions_tree = spirv_grammar_tree.get("instructions");

    try writer.print("pub fn getInstructionInfo(op: Op) InstructionInfo {{\n    return switch (op) {{\n", .{});
    var previous_opcode: i64 = -1;
    for (instructions_tree.array().items()) |instruction_tree| {
        const opcode = instruction_tree.get("opcode").integer();
        if (opcode == previous_opcode) {
            continue;
        }
        previous_opcode = opcode;
        const opname = instruction_tree.get("opname").string();
        const operands_tree = instruction_tree.object().getOrNull("operands");
        try writer.print("        .{s} => .{{ .operands = &[_]OperandType{{ ", .{opname});
        var pushed = false;
        if (operands_tree) |operands| {
            for (0..operands.array().items().len) |i| {
                if (pushed) {
                    try writer.print(", ", .{});
                }
                pushed = true;
                const operand_tree = operands.array().items()[i];
                const kind = operand_tree.get("kind").string();
                if (std.mem.eql(u8, kind, "IdResultType")) {
                    try writer.print(".result_type_id", .{});
                } else if (std.mem.eql(u8, kind, "IdResult")) {
                    try writer.print(".result_id", .{});
                } else if (std.mem.eql(u8, kind, "IdRef")) {
                    try writer.print(".id_ref", .{});
                } else  {
                    try writer.print(".other", .{});
                }
            }
        }
        try writer.print(" }} }},\n", .{});
    }
    try writer.print("    }};\n}}\n", .{});

    // TODO
    //try writer.flush();
}
