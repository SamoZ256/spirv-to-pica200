const std = @import("std");

pub const StorageClass = enum {
    Function,
    Input,
    Output,
    Uniform,
};

const Constant = union {
    u: u32,
    i: i32,
    f: f32,
    b: bool,
};

const Value = struct {
    name: []const u8,
    component_indices: [4]i8,
    array_size: u32,
    array_index: ?*const Value,
    constant: ?Constant,
    ignore_load: bool,

    pub fn init(name: []const u8) Value {
        var self: Value = undefined;
        self.name = name;
        self.component_indices[0] = 0;
        self.component_indices[1] = 1;
        self.component_indices[2] = 2;
        self.component_indices[3] = 3;
        self.array_size = 0;
        self.array_index = null;
        self.constant = null;
        self.ignore_load = false;

        return self;
    }

    pub fn load(self: *Value) Value {
        const result = self;
        result.ignore_load = true;

        return result;
    }

    pub fn indexInto(self: Value, index: *const Value) Value {
        var result = self;
        if (self.array_size != 0 and self.array_index == null) {
            result.array_index = index;
        } else {
            result.component_indices[0] = result.component_indices[index.constant.?.u];
        }

        return result;
    }

    pub fn getName(self: Value, _: std.mem.Allocator) []const u8 {
        return self.name; // TODO: take array index and component indices into account
    }
};

pub const Builder = struct {
    allocator: std.mem.Allocator,
    id_map: std.AutoHashMap(u32, Value),

    pub fn init(allocator: std.mem.Allocator) Builder {
        var self: Builder = undefined;
        self.allocator = allocator;
        self.id_map = std.AutoHashMap(u32, Value).init(self.allocator);

        return self;
    }

    pub fn deinit(self: *Builder) void {
        self.id_map.deinit();
    }

    // Instructions
    pub fn CreateNop(_: *Builder, writer: anytype) !void {
        try writer.printLine("nop", .{});
    }

    pub fn CreateFunction(_: *Builder, writer: anytype) !void {
        try writer.enterScope(".proc main");
    }

    pub fn CreateFunctionEnd(_: *Builder, writer: anytype) !void {
        try writer.leaveScope(".end");
    }

    pub fn CreateLabel(_: *Builder, writer: anytype, id: u32) !void {
        try writer.printLine("label{}", .{id});
    }

    pub fn CreateVariable(self: *Builder, writer: anytype, result: u32, _: u32, storage_class: StorageClass) !void {
        var name: []const u8 = undefined;
        switch (storage_class) {
            .Input => name = "v0", // TODO: get the input index
            .Uniform => name = "uniform", // TODO: get the uniform index
            else => name = "r0", // TODO: query available register
        }

        var value = Value.init(name);
        if (storage_class == .Input or storage_class == .Uniform) {
            value.ignore_load = true;
        }
        // TODO: set component indices and array size
        try self.id_map.put(result, value);
        switch (storage_class) {
            .Uniform => try writer.printLine(".fvec {s}", .{value.getName(self.allocator)}),
            else => {},
        }
    }

    pub fn CreateLoad(self: *Builder, writer: anytype, result: u32, ptr: u32) !void {
        const value = self.id_map.get(ptr);
        if (value.ignore_load) {
            self.id_map.put(result, value.load());
            return;
        }
        self.id_map.put(result, Value.init("r0")); // TODO: query available register
        writer.printLine("mov {}, {}", .{result, ptr});
    }

    pub fn CreateCompositeExtract(self: *Builder, _: anytype, result: u32, composite: u32, indices: []const u32) !void {
        var value = self.id_map.get(composite).?;
        for (indices) |i| {
            const index = self.id_map.get(i);
            if (index) |*ind| {
                value = value.indexInto(ind);
            }
        }
        try self.id_map.put(result, value);
    }
};
