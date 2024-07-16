const std = @import("std");

pub const StorageClass = enum {
    Function,
    Input,
    Output,
    Uniform,
};

const ScalarType = enum {
    Bool,
    Int,
    Uint,
    Float,
};

const Constant = union(ScalarType) {
    Bool: bool,
    Int: i32,
    Uint: u32,
    Float: f32,

    pub fn toIndex(self: Constant) usize {
        return switch (self) {
            .Int => |i| @intCast(i),
            .Uint => |u| u,
            else => std.debug.panic("Invalid array index type\n", .{}),
        };
    }
};

fn getComponentStr(component: anytype) u8 {
    if (component == -1) {
        return ' ';
    }

    return "xyzw"[@intCast(component)];
}

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
            result.component_indices[0] = result.component_indices[index.constant.?.toIndex()];
            result.component_indices[1] = -1;
            result.component_indices[2] = -1;
            result.component_indices[3] = -1;
        }

        return result;
    }

    pub fn getName(self: Value, allocator: std.mem.Allocator) ![]const u8 {
        var array_index_str: []const u8 = "";
        if (self.array_index) |array_ind| {
            array_index_str = try std.fmt.allocPrint(allocator, "[{}]", .{ array_ind.constant.?.toIndex() });
        }
        var component_indices_str: []const u8 = "";
        if (self.component_indices[0] != 0 or self.component_indices[1] != 1 or self.component_indices[2] != 2 or self.component_indices[3] != 3) {
            component_indices_str = try std.fmt.allocPrint(allocator, ".{c}{c}{c}{c}", .{getComponentStr(self.component_indices[0]), getComponentStr(self.component_indices[1]), getComponentStr(self.component_indices[2]), getComponentStr(self.component_indices[3])});
        }

        return try std.fmt.allocPrint(allocator, "{s}{s}{s}", .{self.name, array_index_str, component_indices_str});
    }
};

const TypeId = enum {
    Void,
    Bool,
    Int,
    Float,
    Vector,
    Matrix,
    Array,
    Struct,
};

const Type = union(TypeId) {
    Void: struct {
    },
    Bool: struct {
    },
    Int: struct {
        is_signed: bool,
    },
    Float: struct {
    },
    Vector: struct {
        component_type: *const Type,
        component_count: u32,
    },
    Matrix: struct {
        column_type: *const Type,
        column_count: u32,
    },
    Array: struct {
        element_type: *const Type,
        element_count: u32,
    },
    Struct: struct {
        member_types: []*const Type,
    },
};

pub const Builder = struct {
    allocator: std.mem.Allocator,
    id_map: std.AutoHashMap(u32, Value),
    type_map: std.AutoHashMap(u32, Type),
    //decoration_map: std.AutoHashMap(u32, []const u8),

    // HACK
    register_counter: u32,

    pub fn init(allocator: std.mem.Allocator) Builder {
        var self: Builder = undefined;
        self.allocator = allocator;
        self.id_map = std.AutoHashMap(u32, Value).init(self.allocator);
        self.type_map = std.AutoHashMap(u32, Type).init(self.allocator);
        self.register_counter = 0;

        return self;
    }

    pub fn deinit(self: *Builder) void {
        self.id_map.deinit();
    }

    // Utility
    fn getAvailableRegisterName(self: *Builder) ![]const u8 {
        const result = self.register_counter;
        self.register_counter += 1;

        return std.fmt.allocPrint(self.allocator, "r{}", .{result});
    }

    // Type instructions
    pub fn createVoidType(self: *Builder, result: u32) !void {
        try self.type_map.put(result, Type{ .Void = .{} });
    }

    pub fn createBoolType(self: *Builder, result: u32) !void {
        try self.type_map.put(result, Type{ .Bool = .{} });
    }

    pub fn createIntType(self: *Builder, result: u32, is_signed: bool) !void {
        try self.type_map.put(result, Type{ .Int = .{ .is_signed = is_signed } });
    }

    pub fn createFloatType(self: *Builder, result: u32) !void {
        try self.type_map.put(result, Type{ .Float = .{} });
    }

    pub fn createVectorType(self: *Builder, result: u32, component_type: u32, component_count: u32) !void {
        const component_type_t = &self.type_map.get(component_type).?;
        try self.type_map.put(result, Type{ .Vector = .{ .component_type = component_type_t, .component_count = component_count } });
    }

    pub fn createMatrixType(self: *Builder, result: u32, column_type: u32, column_count: u32) !void {
        const column_type_t = &self.type_map.get(column_type).?;
        try self.type_map.put(result, Type{ .Matrix = .{ .column_type = column_type_t, .column_count = column_count } });
    }

    pub fn createArrayType(self: *Builder, result: u32, element_type: u32, element_count: u32) !void {
        const element_type_t = &self.type_map.get(element_type).?;
        try self.type_map.put(result, Type{ .Array = .{ .element_type = element_type_t, .element_count = element_count } });
    }

    pub fn createStructType(_: *Builder, _: u32, _: []const u32) !void {
        // TODO: uncomment
        //var member_types_t: []*Type = undefined;
        //for (member_types) |member_type| {
        //    const member_type_t = try self.type_map.get(member_type);
        //    member_types_t = member_types_t ++ &member_type_t;
        //}
        //try self.type_map.put(result, Type{ .Struct = .{ .member_types = member_types } });
    }

    // Instructions
    pub fn createMain(_: *Builder, writer: anytype) !void {
        try writer.enterScope(".proc main");
    }

    pub fn createEnd(_: *Builder, writer: anytype) !void {
        try writer.leaveScope(".end");
    }

    pub fn createLabel(_: *Builder, writer: anytype, id: u32) !void {
        try writer.printLineScopeIgnored("label{}:", .{id});
    }

    pub fn createConstant(self: *Builder, writer: anytype, result: u32, ty: u32, val: u32) !void {
        const type_v = self.type_map.get(ty).?;

        const constant: Constant = switch (type_v) {
            .Bool => .{ .Bool = val != 0 },
            .Int => |int| blk: {
                if (int.is_signed) {
                    break :blk .{ .Int = @bitCast(val) };
                } else {
                    break :blk .{ .Uint = val };
                }
            },
            .Float => .{ .Float = @bitCast(val) },
            else => std.debug.panic("Unsupported constant type\n", .{}),
        };

        var value = Value.init("const0"); // TODO: use the result id for naming
        value.constant = constant;
        try self.id_map.put(result, value);

        // Only float constants can be used in the code
        switch (constant) {
            .Float => |f| try writer.printLine(".constf {s}({}, {}, {}, {})", .{try value.getName(self.allocator), f, f, f, f}),
            else => {},
        }
    }

    pub fn createVariable(self: *Builder, writer: anytype, result: u32, _: u32, storage_class: StorageClass) !void {
        var name: []const u8 = undefined;
        switch (storage_class) {
            .Input => name = "v0", // TODO: get the input index
            .Uniform => name = "uniform", // TODO: get the uniform index
            else => name = try self.getAvailableRegisterName(),
        }

        var value = Value.init(name);
        if (storage_class == .Input or storage_class == .Uniform) {
            value.ignore_load = true;
        }
        // TODO: set component indices and array size
        try self.id_map.put(result, value);
        switch (storage_class) {
            .Uniform => try writer.printLine(".fvec {s}", .{try value.getName(self.allocator)}),
            else => {},
        }
    }

    pub fn createNop(_: *Builder, writer: anytype) !void {
        try writer.printLine("nop", .{});
    }

    pub fn createLoad(self: *Builder, writer: anytype, result: u32, ptr: u32) !void {
        const ptr_v = self.id_map.get(ptr).?;
        if (ptr_v.ignore_load) {
            try self.id_map.put(result, ptr_v.load());
            return;
        }
        try self.id_map.put(result, Value.init(try self.getAvailableRegisterName()));
        try writer.printLine("mov {}, {}", .{result, ptr});
    }

    pub fn createStore(self: *Builder, writer: anytype, ptr: u32, val: u32) !void {
        const ptr_v = self.id_map.get(ptr).?;
        const val_v = self.id_map.get(val).?;
        try writer.printLine("mov {s}, {s}", .{try ptr_v.getName(self.allocator), try val_v.getName(self.allocator)});
    }

    pub fn createExtract(self: *Builder, _: anytype, result: u32, composite: u32, indices: []const u32) !void {
        var value = self.id_map.get(composite).?;
        for (indices) |index| {
            var index_v = Value.init("");
            index_v.constant = Constant{ .Uint = index };
            value = value.indexInto(&index_v);
        }
        try self.id_map.put(result, value);
    }

    pub fn createAccessChain(self: *Builder, _: anytype, result: u32, composite: u32, indices: []const u32) !void {
        var value = self.id_map.get(composite).?;
        for (indices) |index| {
            const index_v = self.id_map.get(index);
            if (index_v) |*ind_v| {
                value = value.indexInto(ind_v);
            }
        }
        try self.id_map.put(result, value);
    }

    pub fn createConstruct(self: *Builder, writer: anytype, result: u32, _: u32, components: []const u32) !void {
        var value = Value.init(try self.getAvailableRegisterName());
        for (0..components.len) |i| {
            const component = self.id_map.get(components[i]).?;
            try writer.printLine("mov {s}.{c}, {s}", .{try value.getName(self.allocator), getComponentStr(i), try component.getName(self.allocator)});
        }
        try self.id_map.put(result, value);
    }

    pub fn createAdd(self: *Builder, writer: anytype, result: u32, _: u32, lhs: u32, rhs: u32) !void {
        const lhs_v = self.id_map.get(lhs).?;
        const rhs_v = self.id_map.get(rhs).?;
        const value = Value.init(try self.getAvailableRegisterName());
        try self.id_map.put(result, value);
        // TODO: check how many components the vector has
        try writer.printLine("add {s}, {s}, {s}", .{try value.getName(self.allocator), try lhs_v.getName(self.allocator), try rhs_v.getName(self.allocator)});
    }

    pub fn createVectorTimesScalar(self: *Builder, writer: anytype, result: u32, _: u32, vec: u32, scalar: u32) !void {
        const vec_v = self.id_map.get(vec).?;
        const scalar_v = self.id_map.get(scalar).?;
        const value = Value.init(try self.getAvailableRegisterName());
        try self.id_map.put(result, value);
        // TODO: check how many components the vector has
        try writer.printLine("mul {s}, {s}, {s}.xxxx", .{try value.getName(self.allocator), try vec_v.getName(self.allocator), try scalar_v.getName(self.allocator)});
    }
};
