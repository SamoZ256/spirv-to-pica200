const std = @import("std");

pub const StorageClass = enum {
    function,
    input,
    output,
    uniform,
};

pub const ComparisonMode = enum {
    equal,
    not_equal,
    less_than,
    less_equal,
    greater_than,
    greater_equal,

    pub fn toStr(self: ComparisonMode) []const u8 {
        return switch (self) {
            .equal => "eq",
            .not_equal => "ne",
            .less_than => "lt",
            .less_equal => "le",
            .greater_than => "gt",
            .greater_equal => "ge",
        };
    }

    pub fn opposite(self: ComparisonMode) ComparisonMode {
        return switch (self) {
            .equal => .not_equal,
            .not_equal => .equal,
            .less_than => .greater_equal,
            .less_equal => .greater_than,
            .greater_than => .less_equal,
            .greater_equal => .less_than,
        };
    }
};

pub const Decoration = union(enum) {
    none: void,
    location: u32,
    position: void,
};

pub const DecorationProperties = struct {
    has_location: bool,

    location: u32,
    position: bool,
};

pub const Constant = union(enum) {
    bool: bool,
    int: i32,
    uint: u32,
    float: f32,
    vector_float: [4]f32,

    pub fn toIndex(self: Constant) u32 {
        return switch (self) {
            .int => |i| @intCast(i),
            .uint => |u| u,
            else => std.debug.panic("invalid array index type\n", .{}),
        };
    }

    pub fn toFloat(self: Constant) f32 {
        return switch (self) {
            .float => |f| f,
            else => std.debug.panic("invalid float type\n", .{}),
        };
    }
};

pub fn getComponentStr(component: i8) []const u8 {
    return switch (component) {
        -1 => "",
        0 => "x",
        1 => "y",
        2 => "z",
        3 => "w",
        else => std.debug.panic("invalid component index\n", .{}),
    };
}

pub const Ty = union(enum) {
    void: void,
    bool: void,
    int: struct {
        is_signed: bool,
    },
    float: void,
    vector: struct {
        component_type: *const Type,
        component_count: u32,
    },
    matrix: struct {
        column_type: *const Type,
        column_count: u32,
    },
    array: struct {
        element_type: *const Type,
        element_count: u32,
    },
    structure: struct {
        member_types: []*const Type,
    },

    pub fn getRegisterCount(self: Ty) u32 {
        return switch (self) {
            .void => 0,
            .bool, .int, .float, .vector => 1,
            .matrix => |mtx_type| mtx_type.column_count * mtx_type.column_type.ty.getRegisterCount(),
            .array => |arr_type| arr_type.element_count * arr_type.element_type.ty.getRegisterCount(),
            .structure => |struct_type| blk: {
                var result: u32 = 0;
                for (struct_type.member_types) |member_type| {
                    result += member_type.ty.getRegisterCount();
                }
                break :blk result;
            },
        };
    }

    pub fn getComponentCount(self: Ty) u32 {
        return switch (self) {
            .void => 0,
            .bool, .int, .float => 1,
            .vector => |vector_t| vector_t.component_count,
            .matrix => |matrix_t| matrix_t.column_type.ty.getComponentCount(),
            .array => |array_t| array_t.element_type.ty.getComponentCount(),
            .structure => unreachable,
        };
    }
};

pub const Type = struct {
    id: u32,
    ty: Ty,
};

pub const Value = struct {
    name: []const u8,
    ty: Type, // HACK: this should be *const Type
    component_indices: [4]i8,
    constant: ?Constant,
    is_uniform: bool,

    pub fn init(name: []const u8, ty: Type) Value {
        var self: Value = undefined;
        self.name = name;
        self.ty = ty;
        const component_count = self.ty.ty.getComponentCount();
        for (0..4) |i| {
            if (i < component_count) {
                self.component_indices[i] = @intCast(i);
            } else {
                self.component_indices[i] = -1;
            }
        }
        self.constant = null;
        self.is_uniform = false;

        return self;
    }

    pub fn indexInto(self: *const Value, allocator: std.mem.Allocator, index_v: *const Value) !Value {
        var result = self.*;
        switch (self.ty.ty) {
            .array => |array_type| {
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
        if ((self.component_indices[0] != 0 or self.component_indices[1] != 1 or self.component_indices[2] != 2 or self.component_indices[3] != 3) and
            (self.component_indices[0] != -1 or self.component_indices[1] != -1 or self.component_indices[2] != -1 or self.component_indices[3] != -1)) {
            component_indices_str = try std.fmt.allocPrint(allocator, ".{s}{s}{s}{s}", .{getComponentStr(self.component_indices[0]), getComponentStr(self.component_indices[1]), getComponentStr(self.component_indices[2]), getComponentStr(self.component_indices[3])});
        }

        return try std.fmt.allocPrint(allocator, "{s}{s}", .{self.name, component_indices_str});
    }

    pub fn canBeSrc2(self: *const Value) bool {
        return (self.constant == null and !self.is_uniform);
    }
};

pub fn memberIndexToId(id: u32, member_index: u32) u32 {
    return ((member_index + 1) << 24) | id;
}

pub fn idToMemberIndex(id: u32) struct { id: u32, member_index: u32, is_member: bool } {
    if ((id >> 24) == 0) {
        return .{ .id = id, .member_index = 0, .is_member = false };
    } else {
        return .{ .id = id & 0xFFFFFF, .member_index = (id >> 24) - 1, .is_member = true };
    }
}

pub fn getOutputName(location: u32) []const u8 {
    return switch (location) {
        0 => "normalquat",
        1 => "color",
        2 => "texcoord0",
        3 => "texcoord0w",
        4 => "texcoord1",
        5 => "texcoord2",
        6 => "view",
        7 => "dummy",
        else => std.debug.panic("invalid output location\n", .{}),
    };
}
