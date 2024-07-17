const std = @import("std");

pub const StorageClass = enum {
    Function,
    Input,
    Output,
    Uniform,
};

pub const DecorationType = enum {
    None,
    Location,
    Position,
};

pub const Decoration = union(DecorationType) {
    None: void,
    Location: u32,
    Position: void,
};

const DecorationProperties = struct {
    has_location: bool,

    location: u32,
    position: bool,
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

    pub fn toIndex(self: Constant) u32 {
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

const Ty = union(TypeId) {
    Void: void,
    Bool: void,
    Int: struct {
        is_signed: bool,
    },
    Float: void,
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

    pub fn getRegisterCount(self: Ty) u32 {
        return switch (self) {
            .Void => 0,
            .Bool => 1,
            .Int => 1,
            .Float => 1,
            .Vector => 1,
            .Matrix => |mtx_type| mtx_type.column_count * mtx_type.column_type.ty.getRegisterCount(),
            .Array => |arr_type| arr_type.element_count * arr_type.element_type.ty.getRegisterCount(),
            .Struct => |struct_type| {
                var result: u32 = 0;
                for (struct_type.member_types) |member_type| {
                    result += member_type.ty.getRegisterCount();
                }
                return result;
            },
        };
    }
};

const Type = struct {
    id: u32,
    ty: Ty,
};

const Value = struct {
    id: u32,
    name: []const u8,
    register_index: u32,
    ty: Type, // HACK: this should be *const Type
    component_indices: [4]i8,
    constant: ?Constant,

    pub fn init(id: u32, name: []const u8, register_index: u32, ty: Type) Value {
        var self: Value = undefined;
        self.id = id;
        self.name = name;
        self.register_index = register_index;
        self.ty = ty;
        self.component_indices[0] = 0;
        self.component_indices[1] = 1;
        self.component_indices[2] = 2;
        self.component_indices[3] = 3;
        self.constant = null;

        return self;
    }

    pub fn indexInto(self: *const Value, allocator: std.mem.Allocator, index_v: *const Value) !Value {
        var result = self.*;
        switch (self.ty.ty) {
            .Array => |array_type| {
                result.ty = array_type.element_type.*;
                result.name = try std.fmt.allocPrint(allocator, "{s}[{}]", .{self.name, index_v.constant.?.toIndex()});
            },
            else => {
                result.component_indices[0] = result.component_indices[index_v.constant.?.toIndex()];
                result.component_indices[1] = -1;
                result.component_indices[2] = -1;
                result.component_indices[3] = -1;
            },
        }

        return result;
    }

    pub fn getName(self: *const Value, allocator: std.mem.Allocator) ![]const u8 {
        var component_indices_str: []const u8 = "";
        if (self.component_indices[0] != 0 or self.component_indices[1] != 1 or self.component_indices[2] != 2 or self.component_indices[3] != 3) {
            component_indices_str = try std.fmt.allocPrint(allocator, ".{c}{c}{c}{c}", .{getComponentStr(self.component_indices[0]), getComponentStr(self.component_indices[1]), getComponentStr(self.component_indices[2]), getComponentStr(self.component_indices[3])});
        }

        return try std.fmt.allocPrint(allocator, "{s}{}{s}", .{self.name, self.register_index, component_indices_str});
    }
};

fn memberIndexToId(id: u32, member_index: u32) u32 {
    return ((member_index + 1) << 24) | id;
}

fn idToMemberIndex(id: u32) struct { id: u32, member_index: u32, is_member: bool } {
    if ((id >> 24) == 0) {
        return .{ .id = id, .member_index = 0, .is_member = false };
    } else {
        return .{ .id = id & 0xFFFFFF, .member_index = (id >> 24) - 1, .is_member = true };
    }
}

fn getOutputName(location: u32) []const u8 {
    return switch (location) {
        0 => "normalquat",
        1 => "color",
        2 => "texcoord0",
        3 => "texcoord0w",
        4 => "texcoord1",
        5 => "texcoord2",
        6 => "view",
        7 => "dummy",
        else => std.debug.panic("Invalid output location\n", .{}),
    };
}

const Writer = struct {
    arr: *std.ArrayList(u8),
    in_scope: bool,

    pub fn init(arr: *std.ArrayList(u8)) Writer {
        var self: @This() = undefined;
        self.arr = arr;
        self.in_scope = false;

        return self;
    }

    pub fn printLine(self: *Writer, comptime fmt: []const u8, args: anytype) !void {
        std.debug.print("printLine 1\n", .{});
        if (self.in_scope) {
            _ = try self.arr.writer().write("    ");
        }
        std.debug.print("printLine 2\n", .{});
        try self.arr.writer().print(fmt, args);
        _ = try self.arr.writer().write("\n");
        std.debug.print("printLine 3\n", .{});
    }

    pub fn printLineScopeIgnored(self: *Writer, comptime fmt: []const u8, args: anytype) !void {
        const was_in_scope = self.in_scope;
        self.in_scope = false;
        try self.printLine(fmt, args);
        self.in_scope = was_in_scope;
    }

    pub fn enterScope(self: *Writer, comptime str: []const u8) !void {
        _ = try self.arr.writer().print("{s}\n", .{str});
        self.in_scope = true;
    }

    pub fn leaveScope(self: *Writer, comptime str: []const u8) !void {
        _ = try self.arr.writer().print("{s}\n", .{str});
        self.in_scope = false;
    }
};

pub const Builder = struct {
    allocator: std.heap.ArenaAllocator,
    buffer: [8192]u8,
    fba: std.heap.FixedBufferAllocator,
    id_map: std.AutoHashMap(u32, Value),
    type_map: std.AutoHashMap(u32, Type),
    decoration_map: std.AutoHashMap(u32, DecorationProperties),

    // Writers
    header_array: std.ArrayList(u8),
    header_writer: Writer,
    body_array: std.ArrayList(u8),
    body_writer: Writer,

    // HACK
    register_counter: u32,

    pub fn init(allocator: std.mem.Allocator) Builder {
        var self: Builder = undefined;
        self.allocator = std.heap.ArenaAllocator.init(allocator);
        self.fba = std.heap.FixedBufferAllocator.init(&self.buffer);
        self.id_map = std.AutoHashMap(u32, Value).init(allocator);
        self.type_map = std.AutoHashMap(u32, Type).init(allocator);
        self.decoration_map = std.AutoHashMap(u32, DecorationProperties).init(allocator);

        // Writers
        self.header_array = std.ArrayList(u8).init(self.fba.allocator());
        self.header_writer = Writer.init(&self.header_array);
        self.body_array = std.ArrayList(u8).init(self.fba.allocator());
        self.body_writer = Writer.init(&self.body_array);

        // HACK
        self.register_counter = 0;

        return self;
    }

    pub fn deinit(self: *Builder) void {
        self.body_array.deinit();
        self.header_array.deinit();
        self.decoration_map.deinit();
        self.type_map.deinit();
        self.id_map.deinit();
        self.allocator.deinit();
    }

    pub fn write(self: *Builder, _: anytype) !void {
        _ = try self.header_array.writer().write("Hello");
        try self.header_writer.printLine("Hello2", .{});
        //_ = try writer.write(self.header_array.items);
        //_ = try writer.write(self.body_array.items);
        std.debug.print("{s}\n{s}\n", .{self.header_array.items, self.body_array.items});
    }

    // Utility
    fn getAvailableRegister(self: *Builder, count: u32) u32 {
        const result = self.register_counter;
        self.register_counter += count;

        return result;
    }

    fn getValueName(self: *Builder, value: *const Value) ![]const u8 {
        return value.getName(self.allocator.allocator());
    }

    // Decoration instructions
    pub fn createDecoration(self: *Builder, target_id: u32, decoration: Decoration) !void {
        const decoration_props = try self.decoration_map.getOrPut(target_id);
        if (!decoration_props.found_existing) {
            decoration_props.value_ptr.has_location = false;
        }
        switch (decoration) {
            .Location => |location| {
                decoration_props.value_ptr.has_location = true;
                decoration_props.value_ptr.location = location;
                try self.header_writer.printLine(".out o{} {s}", .{location, getOutputName(location)});
            },
            .Position => {
                decoration_props.value_ptr.position = true;
                try self.header_writer.printLine(".out outpos0 position", .{});
            },
            else => {},
        }
    }

    pub fn createMemberDecoration(self: *Builder, target_id: u32, member_index: u32, decoration: Decoration) !void {
        try self.createDecoration(memberIndexToId(target_id, member_index), decoration);
    }

    // Type instructions
    pub fn createVoidType(self: *Builder, result: u32) !void {
        try self.type_map.put(result, .{ .id = result, .ty = .{ .Void = {} } });
    }

    pub fn createBoolType(self: *Builder, result: u32) !void {
        try self.type_map.put(result, .{ .id = result, .ty = .{ .Bool = {} } });
    }

    pub fn createIntType(self: *Builder, result: u32, is_signed: bool) !void {
        try self.type_map.put(result, .{ .id = result, .ty = .{ .Int = .{ .is_signed = is_signed } } });
    }

    pub fn createFloatType(self: *Builder, result: u32) !void {
        try self.type_map.put(result, .{ .id = result, .ty = .{ .Float = {} } });
    }

    pub fn createVectorType(self: *Builder, result: u32, component_type: u32, component_count: u32) !void {
        const component_type_t = self.type_map.get(component_type);
        if (component_type_t) |*t| {
            try self.type_map.put(result, .{ .id = result, .ty = .{ .Vector = .{ .component_type = t, .component_count = component_count } } });
        }
    }

    pub fn createMatrixType(self: *Builder, result: u32, column_type: u32, column_count: u32) !void {
        const column_type_t = self.type_map.get(column_type);
        if (column_type_t) |*t| {
            try self.type_map.put(result, .{ .id = result, .ty = .{ .Matrix = .{ .column_type = t, .column_count = column_count } } });
        }
    }

    pub fn createArrayType(self: *Builder, result: u32, element_type: u32, element_count: u32) !void {
        const element_type_t = self.type_map.get(element_type);
        if (element_type_t) |*t| {
            try self.type_map.put(result, .{ .id = result, .ty = .{ .Array = .{ .element_type = t, .element_count = element_count } } });
        }
    }

    pub fn createStructType(self: *Builder, result: u32, member_types: []const u32) !void {
        var member_types_t = std.ArrayList(*const Type).init(self.allocator.allocator());
        for (member_types) |member_type| {
            const member_type_t = self.type_map.get(member_type);
            if (member_type_t) |*t| {
                try member_types_t.append(t);
            }
        }
        try self.type_map.put(result, .{ .id = result, .ty = .{ .Struct = .{ .member_types = member_types_t.items } } });
    }

    pub fn createPointerType(self: *Builder, result: u32, element_type: u32) !void {
        const element_type_t = self.type_map.get(element_type).?;
        // Just copy the type
        try self.type_map.put(result, element_type_t);
    }

    // Instructions
    pub fn createMain(self: *Builder) !void {
        std.debug.print("Test 1 passed\n", .{});
        try self.body_writer.enterScope(".proc main");
        std.debug.print("Test 1.1 passed\n", .{});
    }

    pub fn createEnd(self: *Builder) !void {
        try self.body_writer.leaveScope(".end");
    }

    pub fn createLabel(self: *Builder, id: u32) !void {
        std.debug.print("Test 2 passed\n", .{});
        try self.body_writer.printLineScopeIgnored("label{}:", .{id});
        std.debug.print("Test 2.1 passed\n", .{});
    }

    pub fn createConstant(self: *Builder, result: u32, ty: u32, val: u32) !void {
        const type_v = self.type_map.get(ty).?;

        const constant: Constant = switch (type_v.ty) {
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

        var value = Value.init(result, "const", result, type_v); // TODO: use the result id for naming
        value.constant = constant;
        try self.id_map.put(result, value);

        // Only float constants can be used in the code
        switch (constant) {
            .Float => |f| try self.header_writer.printLine(".constf {s}({}, {}, {}, {})", .{try self.getValueName(&value), f, f, f, f}),
            else => {},
        }
    }

    pub fn createVariable(self: *Builder, result: u32, ty: u32, storage_class: StorageClass) !void {
        const type_v = self.type_map.get(ty).?;

        try self.createVariableImpl(result, null, type_v, storage_class);
    }

    pub fn createVariableImpl(self: *Builder, result: u32, parent_type_v: ?Type, type_v: Type, storage_class: StorageClass) !void {
        switch (type_v.ty) {
            .Struct => |struct_t| {
                for (0..struct_t.member_types.len) |i| {
                    const member_t = struct_t.member_types[i];
                    try self.createVariableImpl(memberIndexToId(result, @intCast(i)), type_v, member_t.*, storage_class);
                }
                return;
            },
            else => {},
        }

        var decoration_props = self.decoration_map.get(result);
        // If null, try to fetch it from the type
        if (decoration_props == null) {
            decoration_props = self.decoration_map.get(type_v.id);
            // If still null, fetch it as a member from the parent type
            if (decoration_props == null) {
                // Get the id and member index from result
                const parent_id = idToMemberIndex(result);
                if (parent_id.is_member) {
                    decoration_props = self.decoration_map.get(memberIndexToId(parent_type_v.?.id, parent_id.member_index));
                }
            }
        }

        var name: []const u8 = undefined;
        var register_index: u32 = undefined;
        switch (storage_class) {
            .Input => {
                name = "v";
                register_index = decoration_props.?.location;
            },
            .Output => {
                if (decoration_props.?.position) {
                    name = "outpos";
                    register_index = 0;
                } else {
                    name = "o";
                    register_index = decoration_props.?.location;
                }
            },
            .Uniform => {
                name = "uniform";
                register_index = decoration_props.?.location;
            },
            .Function => {
                name = "r";
                register_index = self.getAvailableRegister(type_v.ty.getRegisterCount());
            },
        }

        var value = Value.init(result, name, register_index, type_v);
        try self.id_map.put(result, value);
        switch (storage_class) {
            .Uniform => try self.header_writer.printLine(".fvec {s}", .{try self.getValueName(&value)}),
            else => {},
        }
    }

    pub fn createNop(self: *Builder) !void {
        try self.body_writer.printLine("nop", .{});
    }

    pub fn createLoad(self: *Builder, result: u32, ptr: u32) !void {
        const ptr_v = self.id_map.get(ptr).?;
        try self.id_map.put(result, ptr_v);
    }

    pub fn createStore(self: *Builder, ptr: u32, val: u32) !void {
        std.debug.print("Test 3 passed\n", .{});
        const ptr_v = self.id_map.get(ptr).?;
        const val_v = self.id_map.get(val).?;
        std.debug.print("Test 3.0.1 passed\n", .{});
        try self.body_writer.printLine("mov {s}, {s}", .{try self.getValueName(&ptr_v), try self.getValueName(&val_v)});

        std.debug.print("Test 3.1 passed\n", .{});
    }

    fn indexToValue(self: *Builder, index: u32, is_id: bool) *const Value {
        if (is_id) {
            return &self.id_map.get(index).?;
        } else {
            var index_v = Value.init(0, "INVALID", 0, .{ .id = 0, .ty = .{ .Int = .{ .is_signed = false } } });
            index_v.constant = Constant{ .Uint = index };

            return &index_v;
        }
    }

    pub fn createAccessChain(self: *Builder, result: u32, ptr: u32, indices: []const u32, indices_are_ids: bool) !void {
        const v = self.id_map.get(ptr);

        // The first index is the member index (if the pointer is a struct)
        var value: Value = undefined;
        if (v) |val| {
            value = val;
        } else {
            const index_v = self.indexToValue(indices[0], indices_are_ids);
            try self.createAccessChain(result, memberIndexToId(ptr, index_v.constant.?.toIndex()), indices[1..], indices_are_ids);
            return;
        }

        for (indices) |index| {
            const index_v = self.indexToValue(index, indices_are_ids);
            value = try value.indexInto(self.allocator.allocator(), index_v);
        }
        try self.id_map.put(result, value);
    }

    pub fn createConstruct(self: *Builder, result: u32, ty: u32, components: []const u32) !void {
        const type_v = self.type_map.get(ty).?;

        const value = Value.init(result, "r", self.getAvailableRegister(type_v.ty.getRegisterCount()), type_v);
        for (0..components.len) |i| {
            const component = self.id_map.get(components[i]).?;
            try self.body_writer.printLine("mov {s}.{c}, {s}", .{try self.getValueName(&value), getComponentStr(i), try self.getValueName(&component)});
        }
        try self.id_map.put(result, value);
    }

    pub fn createAdd(self: *Builder, result: u32, ty: u32, lhs: u32, rhs: u32) !void {
        const type_v = self.type_map.get(ty).?;

        const lhs_v = self.id_map.get(lhs).?;
        const rhs_v = self.id_map.get(rhs).?;
        const value = Value.init(result, "r", self.getAvailableRegister(type_v.ty.getRegisterCount()), type_v);
        try self.id_map.put(result, value);
        // TODO: check how many components the vector has
        try self.body_writer.printLine("add {s}, {s}, {s}", .{try self.getValueName(&value), try self.getValueName(&lhs_v), try self.getValueName(&rhs_v)});
    }

    pub fn createVectorTimesScalar(self: *Builder, result: u32, ty: u32, vec: u32, scalar: u32) !void {
        const type_v = self.type_map.get(ty).?;

        const vec_v = self.id_map.get(vec).?;
        const scalar_v = self.id_map.get(scalar).?;
        const value = Value.init(result, "r", self.getAvailableRegister(type_v.ty.getRegisterCount()), type_v);
        try self.id_map.put(result, value);
        // TODO: check how many components the vector has
        try self.body_writer.printLine("mul {s}, {s}, {s}.xxxx", .{try self.getValueName(&value), try self.getValueName(&vec_v), try self.getValueName(&scalar_v)});
    }
};
