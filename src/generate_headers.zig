const std = @import("std");
const json = @import("json");

pub fn main() !void {
    const spirv_spec_data = @embedFile("spirv.json");

    // Allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const spirv_spec_tree = try json.parse(spirv_spec_data, allocator);
    defer spirv_spec_tree.deinit(allocator);

    const spv_tree = spirv_spec_tree.get("spv");
    const enums_tree = spv_tree.get("enum");

    for (enums_tree.array().items()) |enum_tree| {
        const name = enum_tree.get("Name").string();
        const ty = enum_tree.get("Type").string();
        std.debug.print("Name: {s}, Type: {s}\n", .{name, ty});
        const values_tree = enum_tree.get("Values").object();
        for (values_tree.keys()) |key| {
            const value = values_tree.get(key).integer();
            std.debug.print("\"{s}\" : {}\n", .{key, value});
        }
    }
}
