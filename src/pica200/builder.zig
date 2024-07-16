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

const Value = struct {
    name: []const u8,
    ty: *const Type,
    component_indices: [4]i8,
    constant: ?Constant,

    pub fn init(name: []const u8, ty: *const Type) Value {
        var self: Value = undefined;
        self.name = name;
        self.ty = ty;
        self.component_indices[0] = 0;
        self.component_indices[1] = 1;
        self.component_indices[2] = 2;
        self.component_indices[3] = 3;
        self.constant = null;

        return self;
    }

    pub fn indexInto(self: *const Value, allocator: std.mem.Allocator, index: *const Value) !Value {
        var result = self.*;
        switch (self.ty.*) {
            .Array => |array_type| {
                result.ty = array_type.element_type;
                result.name = try std.fmt.allocPrint(allocator, "{s}[{}]", .{self.name, index.constant.?.toIndex()});
            },
            .Struct => |_| std.debug.panic("STRUCT!!!\n", .{}),
            else => blk: {
                result.component_indices[0] = result.component_indices[index.constant.?.toIndex()];
                result.component_indices[1] = -1;
                result.component_indices[2] = -1;
                result.component_indices[3] = -1;
                break :blk;
            },
        }

        return result;
    }

    pub fn getName(self: *const Value, allocator: std.mem.Allocator) ![]const u8 {
        var component_indices_str: []const u8 = "";
        if (self.component_indices[0] != 0 or self.component_indices[1] != 1 or self.component_indices[2] != 2 or self.component_indices[3] != 3) {
            component_indices_str = try std.fmt.allocPrint(allocator, ".{c}{c}{c}{c}", .{getComponentStr(self.component_indices[0]), getComponentStr(self.component_indices[1]), getComponentStr(self.component_indices[2]), getComponentStr(self.component_indices[3])});
        }

        return try std.fmt.allocPrint(allocator, "{s}{s}", .{self.name, component_indices_str});
    }
};

pub const Builder = struct {
    allocator: std.heap.ArenaAllocator,
    id_map: std.AutoHashMap(u32, Value),
    type_map: std.AutoHashMap(u32, Type),
    //decoration_map: std.AutoHashMap(u32, []const u8),

    // HACK
    register_counter: u32,

    pub fn init(allocator: std.mem.Allocator) Builder {
        var self: Builder = undefined;
        self.allocator = std.heap.ArenaAllocator.init(allocator);
        self.id_map = std.AutoHashMap(u32, Value).init(allocator);
        self.type_map = std.AutoHashMap(u32, Type).init(allocator);
        self.register_counter = 0;

        return self;
    }

    pub fn deinit(self: *Builder) void {
        self.type_map.deinit();
        self.id_map.deinit();
        self.allocator.deinit();
    }

    // Utility
    fn getAvailableRegisterName(self: *Builder) ![]const u8 {
        const result = self.register_counter;
        self.register_counter += 1;

        return std.fmt.allocPrint(self.allocator.allocator(), "r{}", .{result});
    }

    fn getValueName(self: *Builder, value: *const Value) ![]const u8 {
        return value.getName(self.allocator.allocator());
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

    pub fn createStructType(self: *Builder, result: u32, member_types: []const u32) !void {
        var member_types_t = std.ArrayList(*const Type).init(self.allocator.allocator());
        for (member_types) |member_type| {
            const member_type_t = &self.type_map.get(member_type).?;
            try member_types_t.append(member_type_t);
        }
        try self.type_map.put(result, Type{ .Struct = .{ .member_types = member_types_t.items } });
    }

    pub fn createPointerType(self: *Builder, result: u32, element_type: u32) !void {
        const element_type_t = self.type_map.get(element_type).?;
        // Just copy the type
        try self.type_map.put(result, element_type_t);
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
        const type_v = &self.type_map.get(ty).?;

        const constant: Constant = switch (type_v.*) {
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

        var value = Value.init("const0", type_v); // TODO: use the result id for naming
        value.constant = constant;
        try self.id_map.put(result, value);

        // Only float constants can be used in the code
        switch (constant) {
            .Float => |f| try writer.printLine(".constf {s}({}, {}, {}, {})", .{try self.getValueName(&value), f, f, f, f}),
            else => {},
        }
    }

    pub fn createVariable(self: *Builder, writer: anytype, result: u32, ty: u32, storage_class: StorageClass) !void {
        const type_v = &self.type_map.get(ty).?;

        var name: []const u8 = undefined;
        switch (storage_class) {
            .Input => name = "v0", // TODO: get the input index
            .Uniform => name = "uniform", // TODO: get the uniform index
            else => name = try self.getAvailableRegisterName(),
        }

        var value = Value.init(name, type_v);
        // TODO: set component indices and array size
        try self.id_map.put(result, value);
        switch (storage_class) {
            .Uniform => try writer.printLine(".fvec {s}", .{try self.getValueName(&value)}),
            else => {},
        }
    }

    pub fn createNop(_: *Builder, writer: anytype) !void {
        try writer.printLine("nop", .{});
    }

    pub fn createLoad(self: *Builder, _: anytype, result: u32, ptr: u32) !void {
        const ptr_v = self.id_map.get(ptr).?;
        try self.id_map.put(result, ptr_v);
    }

    pub fn createStore(self: *Builder, writer: anytype, ptr: u32, val: u32) !void {
        const ptr_v = self.id_map.get(ptr).?;
        const val_v = self.id_map.get(val).?;
        try writer.printLine("mov {s}, {s}", .{try self.getValueName(&ptr_v), try self.getValueName(&val_v)});
    }

    pub fn createExtract(self: *Builder, _: anytype, result: u32, composite: u32, indices: []const u32) !void {
        var value = self.id_map.get(composite).?;
        for (indices) |index| {
            var index_v = Value.init("", &Type{ .Int = .{ .is_signed = false } });
            index_v.constant = Constant{ .Uint = index };
            value = try value.indexInto(self.allocator.allocator(), &index_v);
        }
        try self.id_map.put(result, value);
    }

    pub fn createAccessChain(self: *Builder, _: anytype, result: u32, composite: u32, indices: []const u32) !void {
        var value = self.id_map.get(composite).?;
        for (indices) |index| {
            const index_v = self.id_map.get(index);
            if (index_v) |*ind_v| {
                value = try value.indexInto(self.allocator.allocator(), ind_v);
            }
        }
        try self.id_map.put(result, value);
    }

    pub fn createConstruct(self: *Builder, writer: anytype, result: u32, ty: u32, components: []const u32) !void {
        const type_v = &self.type_map.get(ty).?;

        const value = Value.init(try self.getAvailableRegisterName(), type_v);
        for (0..components.len) |i| {
            const component = self.id_map.get(components[i]).?;
            try writer.printLine("mov {s}.{c}, {s}", .{try self.getValueName(&value), getComponentStr(i), try self.getValueName(&component)});
        }
        try self.id_map.put(result, value);
    }

    pub fn createAdd(self: *Builder, writer: anytype, result: u32, ty: u32, lhs: u32, rhs: u32) !void {
        const type_v = &self.type_map.get(ty).?;

        const lhs_v = self.id_map.get(lhs).?;
        const rhs_v = self.id_map.get(rhs).?;
        const value = Value.init(try self.getAvailableRegisterName(), type_v);
        try self.id_map.put(result, value);
        // TODO: check how many components the vector has
        try writer.printLine("add {s}, {s}, {s}", .{try self.getValueName(&value), try self.getValueName(&lhs_v), try self.getValueName(&rhs_v)});
    }

    pub fn createVectorTimesScalar(self: *Builder, writer: anytype, result: u32, ty: u32, vec: u32, scalar: u32) !void {
        const type_v = &self.type_map.get(ty).?;

        const vec_v = self.id_map.get(vec).?;
        const scalar_v = self.id_map.get(scalar).?;
        const value = Value.init(try self.getAvailableRegisterName(), type_v);
        try self.id_map.put(result, value);
        // TODO: check how many components the vector has
        try writer.printLine("mul {s}, {s}, {s}.xxxx", .{try self.getValueName(&value), try self.getValueName(&vec_v), try self.getValueName(&scalar_v)});
    }
};
