const std = @import("std");

const Value = struct {
    component_indices: [4]i8,
    array_size: u32,
    array_index: ?*Value,
    ignore_load: bool,

    pub fn init(id: u32) Value {
        const self: Value = undefined;
        self.component_indices[0] = 0;
        self.component_indices[1] = 1;
        self.component_indices[2] = 2;
        self.component_indices[3] = 3;
        self.array_size = 1;
        self.ignore_load = false;

        return self;
    }

    pub fn load(self: *Value) Value {
        const result = self;
        result.ignore_load = true;

        return result;
    }

    pub fn index(self: Value, index: *Value) Value {
        const result = self;
        result.array_size = 1;
        result.component_indices[0] = self.component_indices[index];
        result.component_indices[1] = 0;
        result.component_indices[2] = 0;
        result.component_indices[3] = 0;

        return result;
    }
};

pub const Builder = struct {
    id_map: std.AutoHashMap(u32, *Value),

    pub fn init() Builder {
        const self: Builder = undefined;
        self.id_map = std.AutoHashMap(u32, *Value).init();

        return self;
    }

    pub fn deinit(self: *Builder) void {
        self.id_map.deinit();
    }

    // Instructions
    pub fn CreateNop(self: *Builder, writer: anytype) !void {
        try writer.printLine("nop", .{});
    }

    pub fn CreateFunction(self: *Builder, writer: anytype) !void {
        try writer.enterScope(".proc main")
    }

    pub fn CreateFunctionEnd(self: *Builder, writer: anytype) !void {
        try writer.leaveScope(".end");
    }

    pub fn CreateLabel(self: *Builder, writer: anytype, id: u32) !void {
        try writer.printLine("label{}", .{id});
    }

    pub fn CreateLoad(self: *Builder, writer: anytype, result: u32, ptr: u32) !void {
        const value = self.id_map.get(ptr);
        if (value.ignore_load) {
            self.id_map.put(result, value.load());
            return;
        }
        // TODO: do something if load is not ignored
    }

    pub fn CreateCompositeExtract(self: *Builder, writer: anytype, result: u32, composite: u32, indices: []const u32) !void {
        const value = self.id_map.get(composite);
        for (indices) |index| {
            value = value.index(index);
        }
        self.id_map.put(result, value);
    }
};
