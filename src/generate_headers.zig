const std = @import("std");

pub fn main() !void {
    const spirv_spec_data = @embedFile("spirv.json");

    // Allocator
    const gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer gpa.deinit();

    var parser = std.json.Parser.init(gpa.allocator(), false);
    defer parser.deinit();

    var tree = try parser.parse(spirv_spec_data);
    defer tree.deinit();

    // Access the fields value via .get() method
    const spv_tree = tree.root.Object.get("spv").?;
    const enum_tree = spv_tree.get("b").?;
    for (enum_tree) |enum_node| {
        const enum_name = enum_node.key;
        const enum_value = enum_node.value.get("value").?;
        const enum_description = enum_node.value.get("description").?;

        // Print the enum name, value and description
        std.debug.print("Enum: {}, Value: {}, Description: {}\n", enum_name, enum_value, enum_description);
    }
}
