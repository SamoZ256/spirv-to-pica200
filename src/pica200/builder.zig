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

    pub fn load(self: Value) Value {
        var result = self;
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
        try writer.printLineScopeIgnored("label{}:", .{id});
    }

    pub fn CreateConstant(self: *Builder, writer: anytype, result: u32, _: u32, val: u32) !void {
        // HACK
        const constant = Constant{ .f = @bitCast(val) };

        var value = Value.init("const0"); // TODO: use the result id for naming
        value.constant = constant;
        try self.id_map.put(result, value);
        try writer.printLine(".constf {s}({}, {}, {}, {})", .{value.getName(self.allocator), constant.f, constant.f, constant.f, constant.f});
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
        const ptr_v = self.id_map.get(ptr).?;
        if (ptr_v.ignore_load) {
            try self.id_map.put(result, ptr_v.load());
            return;
        }
        try self.id_map.put(result, Value.init("r0")); // TODO: query available register
        try writer.printLine("mov {}, {}", .{result, ptr});
    }

    pub fn CreateStore(self: *Builder, writer: anytype, ptr: u32, val: u32) !void {
        const ptr_v = self.id_map.get(ptr).?;
        const val_v = self.id_map.get(val).?;
        try writer.printLine("mov {s}, {s}", .{ptr_v.getName(self.allocator), val_v.getName(self.allocator)});
    }

    pub fn CreateExtract(self: *Builder, _: anytype, result: u32, composite: u32, indices: []const u32) !void {
        var value = self.id_map.get(composite).?;
        for (indices) |index| {
            var index_v = Value.init("");
            index_v.constant = Constant{ .u = index };
            value = value.indexInto(&index_v);
        }
        try self.id_map.put(result, value);
    }

    pub fn CreateAccessChain(self: *Builder, _: anytype, result: u32, composite: u32, indices: []const u32) !void {
        var value = self.id_map.get(composite).?;
        for (indices) |index| {
            const index_v = self.id_map.get(index);
            if (index_v) |*ind_v| {
                value = value.indexInto(ind_v);
            }
        }
        try self.id_map.put(result, value);
    }

    pub fn CreateConstruct(self: *Builder, writer: anytype, result: u32, _: u32, components: []const u32) !void {
        var value = Value.init("r0"); // TODO: query available register
        for (0..components.len) |i| {
            const component = self.id_map.get(components[i]).?;
            try writer.printLine("mov {s}.{c}, {s}", .{value.getName(self.allocator), "xyzw"[i], component.getName(self.allocator)});
        }
        try self.id_map.put(result, value);
    }
};
