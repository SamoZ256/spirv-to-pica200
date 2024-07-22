const std = @import("std");
const writer = @import("writer.zig");
const base = @import("base.zig");

const ConstantDeclaration = struct {
    index: u32,
    zero_constant: base.Constant,
    values: [4]base.Constant,
    counter: u8,

    pub fn init(index: *u32, zero_constant: base.Constant) ConstantDeclaration {
        var self: ConstantDeclaration = undefined;
        self.index = index.*;
        self.zero_constant = zero_constant;
        self.values = [_]base.Constant{zero_constant, zero_constant, zero_constant, zero_constant};
        self.counter = 0;

        index.* += 1;

        return self;
    }

    pub fn push(self: *ConstantDeclaration, val: base.Constant) void {
        self.values[self.counter] = val;
        self.counter += 1;
    }

    pub fn flush(self: *const ConstantDeclaration, allocator: std.mem.Allocator, w: *writer.Writer) !void {
        if (self.counter != 0) {
            const prefix: u8 = switch (self.values[0]) {
                .int => 'i',
                .float => 'f',
                else => unreachable,
            };

            try w.print(".const{c} shared_const{}(", .{prefix, self.index});
            for (0..4) |i| {
                if (i != 0) {
                    _ = try w.print(", ", .{});
                }
                _ = try w.print("{s}", .{try self.values[i].toStr(allocator)});
            }
            _ = try w.printLine(")", .{});
        }
    }

    pub fn flushIfFull(self: *ConstantDeclaration, allocator: std.mem.Allocator, w: *writer.Writer, index: *u32) !void {
        if (self.counter >= 4) {
            _ = try self.flush(allocator, w);
            self.* = ConstantDeclaration.init(index, self.zero_constant);
        }
    }
};

const REGISTER_COUNT: u8 = 16;

pub const Builder = struct {
    allocator: std.heap.ArenaAllocator,
    buffer: [64 * 1024]u8,
    fba: std.heap.FixedBufferAllocator,
    id_map: std.AutoHashMap(u32, base.Value),
    type_map: std.AutoHashMap(u32, base.Type),
    decoration_map: std.AutoHashMap(u32, base.DecorationProperties),

    // Writers
    uniforms: writer.Writer,
    constants: writer.Writer,
    aliases: writer.Writer,
    outputs: writer.Writer,
    body: writer.Writer,

    constant_counter: u32,
    int_constant: ConstantDeclaration,
    float_constant: ConstantDeclaration,

    registers_occupancy: [16]bool,
    temporary_registers: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) !Builder {
        var self: Builder = undefined;
        self.allocator = std.heap.ArenaAllocator.init(allocator);
        self.fba = std.heap.FixedBufferAllocator.init(&self.buffer);
        self.id_map = std.AutoHashMap(u32, base.Value).init(allocator);
        self.type_map = std.AutoHashMap(u32, base.Type).init(allocator);
        // Allocate enough space for the all the types
        try self.type_map.ensureTotalCapacity(512);
        // Lock the pointers so that we can safely store them in the Ty structure as *const Type
        self.type_map.lockPointers();
        self.decoration_map = std.AutoHashMap(u32, base.DecorationProperties).init(allocator);
        self.constant_counter = 1;
        self.registers_occupancy = [1]bool{false} ** 16;
        self.temporary_registers = std.ArrayList(u8).init(allocator);

        return self;
    }

    pub fn initWriters(self: *Builder) !void {
        self.uniforms = writer.Writer.init(self.fba.allocator());
        self.constants = writer.Writer.init(self.fba.allocator());
        self.aliases = writer.Writer.init(self.fba.allocator());
        self.outputs = writer.Writer.init(self.fba.allocator());
        self.body = writer.Writer.init(self.fba.allocator());

        // Constants
        try self.constants.printLine(".constf shared_const0(0.0, 1.0, 0.0174532925, 57.295779513)", .{});
        try self.aliases.printLine(".alias zeros shared_const0.xxxx", .{});
        try self.aliases.printLine(".alias ones shared_const0.yyyy", .{});
        try self.aliases.printLine(".alias deg_to_rad shared_const0.zzzz", .{});
        try self.aliases.printLine(".alias rad_to_deg shared_const0.wwww", .{});

        self.int_constant = ConstantDeclaration.init(&self.constant_counter, .{ .int = 0 });
        self.float_constant = ConstantDeclaration.init(&self.constant_counter, .{ .float = 0.0 });
    }

    pub fn deinitWriters(self: *Builder) void {
        self.body.deinit();
        self.outputs.deinit();
        self.constants.deinit();
        self.aliases.deinit();
        self.uniforms.deinit();
    }

    pub fn deinit(self: *Builder) void {
        self.temporary_registers.deinit();
        self.type_map.unlockPointers();
        self.decoration_map.deinit();
        self.type_map.deinit();
        self.id_map.deinit();
        self.allocator.deinit();
    }

    pub fn write(self: *Builder, w: anytype) !void {
        try self.int_constant.flush(self.allocator.allocator(), &self.constants);
        try self.float_constant.flush(self.allocator.allocator(), &self.constants);

        _ = try w.write(self.uniforms.arr.items);
        _ = try w.write("\n");
        _ = try w.write(self.constants.arr.items);
        _ = try w.write("\n");
        _ = try w.write(self.aliases.arr.items);
        _ = try w.write("\n");
        _ = try w.write(self.outputs.arr.items);
        _ = try w.write("\n");
        _ = try w.write(self.body.arr.items);
        _ = try w.write("\n");
    }

    pub fn releaseId(self: *Builder, id: u32) void {
        const value = self.id_map.get(id);
        if (value) |v| {
            if (v.register != base.INVALID_REGISTER) {
                self.registers_occupancy[v.register] = false;
            }
        }
    }

    pub fn releaseTempRegisters(self: *Builder) void {
        for (self.temporary_registers.items) |register| {
            self.registers_occupancy[register] = false;
        }
        self.temporary_registers.clearAndFree();
    }

    // Utility
    fn getAvailableRegister(self: *Builder) u8 {
        var register: u8 = base.INVALID_REGISTER;
        for (0..16) |i| {
            if (!self.registers_occupancy[i]) {
                register = @intCast(i);
                self.registers_occupancy[i] = true;
                break;
            }
        }

        if (register == base.INVALID_REGISTER) {
            std.debug.panic("no available registers\n", .{});
        }

        return register;
    }

    fn getValueName(self: *Builder, value: *const base.Value) ![]const u8 {
        return value.getName(self.allocator.allocator());
    }

    fn indexToValue(self: *Builder, index: u32, is_id: bool) !*const base.Value {
        if (is_id) {
            return self.id_map.getPtr(index).?;
        } else {
            const constant = base.Constant{ .uint = index };
            var index_v = base.Value.init(try constant.toStr(self.allocator.allocator()), base.INVALID_REGISTER, .{ .id = 0, .ty = .{ .int = .{ .is_signed = false } } });
            index_v.constant = constant;
            // HACK: set the swizzle to .xyzw so as to not print the swizzle
            for (0..4) |i| {
                index_v.swizzle[i] = @intCast(i);
            }

            return &index_v;
        }
    }

    fn swapIfNeeded(self: *Builder, src1: *base.Value, src2: *base.Value) !bool {
        if (!src2.canBeSrc2()) {
            if (!src1.canBeSrc2()) {
                // If neither can be src2, create a temporary register
                var tmp = try self.createTempValue(src2.ty);
                tmp.swizzle = src2.swizzle;
                _ = try self.body.printLine("mov {s}, {s}", .{try self.getValueName(&tmp), try self.getValueName(src2)});
                src2.* = tmp;

                return false;
            }
            const tmp = src1.*;
            src1.* = src2.*;
            src2.* = tmp;

            return true;
        }

        return false;
    }

    fn createTempValue(self: *Builder, ty: base.Type) !base.Value {
        const register = self.getAvailableRegister();
        try self.temporary_registers.append(register);

        return base.Value.init("r", register, ty);
    }

    // Decoration instructions
    pub fn createDecoration(self: *Builder, target_id: u32, decoration: base.Decoration) !void {
        const decoration_props = try self.decoration_map.getOrPut(target_id);
        if (!decoration_props.found_existing) {
            decoration_props.value_ptr.has_location = false;
        }
        switch (decoration) {
            .location => |location| {
                decoration_props.value_ptr.has_location = true;
                decoration_props.value_ptr.location = location;
            },
            .position => {
                decoration_props.value_ptr.position = true;
            },
            else => {},
        }
    }

    pub fn createMemberDecoration(self: *Builder, target_id: u32, member_index: u32, decoration: base.Decoration) !void {
        try self.createDecoration(base.memberIndexToId(target_id, member_index), decoration);
    }

    // Type instructions
    pub fn createVoidType(self: *Builder, result: u32) void {
        self.type_map.putAssumeCapacity(result, .{ .id = result, .ty = .{ .void = {} } });
    }

    pub fn createBoolType(self: *Builder, result: u32) void {
        self.type_map.putAssumeCapacity(result, .{ .id = result, .ty = .{ .boolean = {} } });
    }

    pub fn createIntType(self: *Builder, result: u32, is_signed: bool) void {
        self.type_map.putAssumeCapacity(result, .{ .id = result, .ty = .{ .int = .{ .is_signed = is_signed } } });
    }

    pub fn createFloatType(self: *Builder, result: u32) void {
        self.type_map.putAssumeCapacity(result, .{ .id = result, .ty = .{ .float = {} } });
    }

    pub fn createVectorType(self: *Builder, result: u32, component_type: u32, component_count: u32) void {
        const component_type_t = self.type_map.getPtr(component_type);
        if (component_type_t) |t| {
            self.type_map.putAssumeCapacity(result, .{ .id = result, .ty = .{ .vector = .{ .component_type = t, .component_count = component_count } } });
        }
    }

    pub fn createMatrixType(self: *Builder, result: u32, column_type: u32, column_count: u32) void {
        const column_type_t = self.type_map.getPtr(column_type);
        if (column_type_t) |t| {
            // Matrix is just an array of vectors
            self.type_map.putAssumeCapacity(result, .{ .id = result, .ty = .{ .array = .{ .element_type = t, .element_count = column_count } } });
        }
    }

    pub fn createArrayType(self: *Builder, result: u32, element_type: u32, element_count: u32) void {
        const element_type_t = self.type_map.getPtr(element_type);
        const element_count_v = self.id_map.get(element_count).?;
        if (element_type_t) |t| {
            self.type_map.putAssumeCapacity(result, .{ .id = result, .ty = .{ .array = .{ .element_type = t, .element_count = element_count_v.constant.?.toIndex() } } });
        }
    }

    pub fn createStructType(self: *Builder, result: u32, member_types: []const u32) !void {
        var member_types_t = std.ArrayList(*const base.Type).init(self.allocator.allocator());
        for (member_types) |member_type| {
            const member_type_t = self.type_map.getPtr(member_type);
            if (member_type_t) |t| {
                try member_types_t.append(t);
            }
        }
        self.type_map.putAssumeCapacity(result, .{ .id = result, .ty = .{ .structure = .{ .member_types = member_types_t.items } } });
    }

    pub fn createPointerType(self: *Builder, result: u32, element_type: u32) void {
        const element_type_t = self.type_map.get(element_type).?;
        // Just copy the type
        self.type_map.putAssumeCapacity(result, element_type_t);
    }

    // Instructions
    pub fn createMain(self: *Builder) !void {
        try self.body.enterScope(".proc main");
    }

    pub fn createEnd(self: *Builder) !void {
        try self.body.leaveScope(".end");
    }

    pub fn createLabel(self: *Builder, id: u32) !void {
        try self.body.printLineScopeIgnored("label{}:", .{id});
    }

    pub fn createConstant(self: *Builder, result: u32, ty: u32, val: u32) !void {
        const type_v = self.type_map.get(ty).?;

        const constant: base.Constant = switch (type_v.ty) {
            .boolean => .{ .boolean = val != 0 },
            .int => |int| blk: {
                if (int.is_signed) {
                    break :blk .{ .int = @bitCast(val) };
                } else {
                    break :blk .{ .uint = val };
                }
            },
            .float => .{ .float = @bitCast(val) },
            else => std.debug.panic("unsupported constant type\n", .{}),
        };

        var value = base.Value.init(try std.fmt.allocPrint(self.allocator.allocator(), "const{}", .{result}), base.INVALID_REGISTER, type_v);
        value.constant = constant;
        try self.id_map.put(result, value);

        // TODO: move this into a helper function
        const constant_index = switch (constant) {
            .int => blk: {
                try self.int_constant.flushIfFull(self.allocator.allocator(), &self.constants, &self.constant_counter);
                const component_index = self.int_constant.counter;
                self.int_constant.push(constant);
                break :blk .{ self.int_constant.index, component_index };
            },
            .float => blk: {
                try self.float_constant.flushIfFull(self.allocator.allocator(), &self.constants, &self.constant_counter);
                const component_index = self.float_constant.counter;
                self.float_constant.push(constant);
                break :blk .{ self.float_constant.index, component_index };
            },
            else => .{ 0, 0 },
        };

        if (constant_index[0] != 0) {
            const swizzle: u8 = switch (constant_index[1]) {
                0 => 'x',
                1 => 'y',
                2 => 'z',
                3 => 'w',
                else => unreachable
            };

            try self.aliases.printLine(".alias {s} shared_const{}.{c}{c}{c}{c}", .{try value.getNameWithoutSwizzle(self.allocator.allocator()), constant_index[0], swizzle, swizzle, swizzle, swizzle});
        }
    }

    // TODO: support types other than vector of floats
    pub fn createConstantComposite(self: *Builder, result: u32, ty: u32, constituents: []const u32) !void {
        const type_v = self.type_map.get(ty).?;

        const constant: base.Constant = switch (type_v.ty) {
            .vector => |vector| blk: {
                var values: [4]f32 = undefined;
                for (0..4) |i| {
                    if (i < vector.component_count) {
                        // TODO: support other vector types as well
                        values[i] = self.id_map.get(constituents[i]).?.constant.?.toFloat();
                    } else {
                        values[i] = 0.0;
                    }
                }
                break :blk .{ .vector_float = values };
            },
            else => std.debug.panic("unsupported constant composite type\n", .{}),
        };

        var value = base.Value.init(try std.fmt.allocPrint(self.allocator.allocator(), "const{}", .{result}), base.INVALID_REGISTER, type_v);
        value.constant = constant;
        try self.id_map.put(result, value);

        switch (constant) {
            .vector_float => |vector| {
                try self.constants.printLine(".const{c} {s}({}, {}, {}, {})", .{type_v.ty.getPrefix(), try value.getNameWithoutSwizzle(self.allocator.allocator()), vector[0], vector[1], vector[2], vector[3]});
            },
            else => unreachable,
        }
    }

    pub fn createVariable(self: *Builder, result: u32, ty: u32, storage_class: base.StorageClass) !void {
        const type_v = self.type_map.get(ty).?;

        try self.createVariableImpl(result, null, type_v, storage_class);
    }

    pub fn createVariableImpl(self: *Builder, result: u32, parent_type_v: ?base.Type, type_v: base.Type, storage_class: base.StorageClass) !void {
        switch (type_v.ty) {
            .structure => |struct_t| {
                for (0..struct_t.member_types.len) |i| {
                    const member_t = struct_t.member_types[i];
                    try self.createVariableImpl(base.memberIndexToId(result, @intCast(i)), type_v, member_t.*, storage_class);
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
                const parent_id = base.idToMemberIndex(result);
                if (parent_id.is_member) {
                    decoration_props = self.decoration_map.get(base.memberIndexToId(parent_type_v.?.id, parent_id.member_index));
                }
            }
        }

        var register: u8 = base.INVALID_REGISTER;
        const name = try switch (storage_class) {
            .input => try std.fmt.allocPrint(self.allocator.allocator(), "v{}", .{decoration_props.?.location}),
            .output => blk: {
                if (decoration_props.?.position) {
                    try self.outputs.printLine(".out outpos position", .{});
                    break :blk "outpos";
                } else if (decoration_props.?.has_location) {
                    const location = decoration_props.?.location;
                    const output_name = base.getOutputName(location);
                    const name = try std.fmt.allocPrint(self.allocator.allocator(), "out{s}", .{output_name});
                    try self.outputs.printLine(".out {s} {s}", .{name, output_name});
                    break :blk name;
                } else {
                    //std.log.warn("output without decoration\n", .{});
                    break :blk "INVALID_OUT";
                }
            },
            .uniform => std.fmt.allocPrint(self.allocator.allocator(), "uniform{}", .{decoration_props.?.location}),
            .function => blk: {
                register = self.getAvailableRegister();
                break :blk "r";
            },
        };

        var value = base.Value.init(name, register, type_v);
        switch (storage_class) {
            .uniform => {
                value.is_uniform = true;
                try self.uniforms.printLine(".{c}vec {s}{s}", .{type_v.ty.getPrefix(), try value.getNameWithoutSwizzle(self.allocator.allocator()), try type_v.ty.getSuffix(self.allocator.allocator())});
            },
            else => {},
        }
        try self.id_map.put(result, value);
    }

    pub fn createNop(self: *Builder) !void {
        try self.body.printLine("nop", .{});
    }

    pub fn createLoad(self: *Builder, result: u32, ptr: u32) !void {
        const ptr_v = self.id_map.get(ptr).?;
        try self.id_map.put(result, ptr_v);
    }

    pub fn createStore(self: *Builder, ptr: u32, val: u32) !void {
        const p_v = self.id_map.get(ptr);

        var ptr_v: base.Value = undefined;
        if (p_v) |v| {
            ptr_v = v;
        } else {
            var i: u32 = 0;
            while (true) {
                const id = base.memberIndexToId(ptr, i);
                if (!self.id_map.contains(id)) {
                    break;
                }
                try self.createStore(id, base.memberIndexToId(val, i));
                i += 1;
            }
            return;
        }

        const val_v = self.id_map.get(val).?;
        try self.body.printLine("mov {s}, {s}", .{try self.getValueName(&ptr_v), try self.getValueName(&val_v)});
    }

    pub fn createAccessChain(self: *Builder, result: u32, ptr: u32, indices: []const u32, indices_are_ids: bool) !void {
        const v = self.id_map.get(ptr);

        // The first index is the member index (if the pointer is a struct)
        var value: base.Value = undefined;
        if (v) |val| {
            value = val;
        } else {
            const index_v = try self.indexToValue(indices[0], indices_are_ids);
            try self.createAccessChain(result, base.memberIndexToId(ptr, index_v.constant.?.toIndex()), indices[1..], indices_are_ids);
            return;
        }

        for (indices) |index| {
            const index_v = try self.indexToValue(index, indices_are_ids);
            value = try value.indexInto(self.allocator.allocator(), index_v);
        }
        try self.id_map.put(result, value);
    }

    pub fn createConstruct(self: *Builder, result: u32, ty: u32, components: []const u32) !void {
        const type_v = self.type_map.get(ty).?;

        var value = base.Value.init("r", self.getAvailableRegister(), type_v);
        try self.id_map.put(result, value);
        for (0..components.len) |i| {
            const component = self.id_map.get(components[i]).?;
            const index_v = try self.indexToValue(@intCast(i), false);
            try self.body.printLine("mov {s}, {s}", .{try self.getValueName(&try value.indexInto(self.allocator.allocator(), index_v)), try self.getValueName(&component)});
        }
    }

    // TODO: optimize this
    pub fn createSelect(self: *Builder, result: u32, ty: u32, cond: u32, a: u32, b: u32) !void {
        const type_v = self.type_map.get(ty).?;

        const cond_v = self.id_map.get(cond).?;
        const a_v = self.id_map.get(a).?;
        const b_v = self.id_map.get(b).?;
        const value = base.Value.init("r", self.getAvailableRegister(), type_v);
        try self.id_map.put(result, value);

        // If true
        try self.body.printLine("slt {s}, zeros, -{s}", .{try self.getValueName(&value), try self.getValueName(&cond_v)});
        try self.body.printLine("mul {s}, {s}", .{try self.getValueName(&value), try self.getValueName(&a_v)});

        // If false
        const temp1_v = try self.createTempValue(type_v);
        const temp2_v = try self.createTempValue(type_v);
        // Subtract 1 from the condition so that it is 0 if true and -1 if false and therefore can be used with slt
        try self.body.printLine("add {s}, -ones, {s}", .{try self.getValueName(&temp1_v), try self.getValueName(&cond_v)});
        try self.body.printLine("slt {s}, zeros, {s}", .{try self.getValueName(&temp2_v), try self.getValueName(&temp1_v)});
        try self.body.printLine("mul {s}, {s}", .{try self.getValueName(&temp2_v), try self.getValueName(&b_v)});
        try self.body.printLine("add {s}, {s}, {s}", .{try self.getValueName(&value), try self.getValueName(&value), try self.getValueName(&temp2_v)});
    }

    // negate can have 3 possible values: -1 => negate lhs, 0 => don't negate, 1 => negate rhs
    pub fn createAdd(self: *Builder, result: u32, ty: u32, lhs: u32, rhs: u32, negate: i8) !void {
        const type_v = self.type_map.get(ty).?;

        var lhs_v = self.id_map.get(lhs).?;
        var rhs_v = self.id_map.get(rhs).?;
        var neg = negate;
        if (try self.swapIfNeeded(&lhs_v, &rhs_v)) {
            neg = -neg;
        }

        const value = base.Value.init("r", self.getAvailableRegister(), type_v);
        try self.id_map.put(result, value);

        const negate1_str = if (neg == -1) "-" else "";
        const negate2_str = if (neg ==  1) "-" else "";
        // TODO: check how many components the vector has
        try self.body.printLine("add {s}, {s}{s}, {s}{s}", .{try self.getValueName(&value), negate1_str, try self.getValueName(&lhs_v), negate2_str, try self.getValueName(&rhs_v)});
    }

    pub fn createMul(self: *Builder, result: u32, ty: u32, lhs: u32, rhs: u32, invert: bool) !void {
        const type_v = self.type_map.get(ty).?;

        var lhs_v = self.id_map.get(lhs).?;
        var rhs_v = self.id_map.get(rhs).?;
        _ = try self.swapIfNeeded(&lhs_v, &rhs_v);
        const value = base.Value.init("r", self.getAvailableRegister(), type_v);
        try self.id_map.put(result, value);

        if (invert) {
            var new_rhs_v = try self.createTempValue(type_v);
            // TODO: check how many components
            for (0..4) |i| {
                const index_v = try self.indexToValue(@intCast(i), false);
                try self.body.printLine("rcp {s}, {s}", .{try self.getValueName(&try new_rhs_v.indexInto(self.allocator.allocator(), index_v)), try self.getValueName(&rhs_v)});
            }
            rhs_v = new_rhs_v;
        }
        try self.body.printLine("mul {s}, {s}, {s}", .{try self.getValueName(&value), try self.getValueName(&lhs_v), try self.getValueName(&rhs_v)});
    }

    pub fn createMatrixTimesMatrix(_: *Builder, _: u32, _: u32, _: u32, _: u32) !void {
        std.debug.panic("matrix times matrix not implemented\n", .{});
    }

    pub fn createMatrixTimesVector(self: *Builder, result: u32, _: u32, mat: u32, vec: u32) !void {
        var mat_v = self.id_map.get(mat).?;
        var vec_v = self.id_map.get(vec).?;

        const value = base.Value.init("r", self.getAvailableRegister(), vec_v.ty);
        try self.id_map.put(result, value);

        // TODO: check for how many components
        for (0..4) |i| {
            const index_v = try self.indexToValue(@intCast(i), false);
            const val = try value.indexInto(self.allocator.allocator(), index_v);
            const mtx = try mat_v.indexInto(self.allocator.allocator(), index_v);
            try self.body.printLine("dp4 {s}, {s}, {s}", .{try self.getValueName(&val), try self.getValueName(&mtx), try self.getValueName(&vec_v)});
        }
    }

    pub fn createCmp(self: *Builder, result: u32, ty: u32, lhs: u32, rhs: u32, cmp_mode: base.ComparisonMode) !void {
        const type_v = self.type_map.get(ty).?;

        var lhs_v = self.id_map.get(lhs).?;
        var rhs_v = self.id_map.get(rhs).?;
        var c_mode = cmp_mode;
        if (try self.swapIfNeeded(&lhs_v, &rhs_v)) {
            c_mode = c_mode.opposite();
        }
        const value = base.Value.init("r", self.getAvailableRegister(), type_v);
        try self.id_map.put(result, value);

        const cmp_str = c_mode.toStr();
        //const cmp2_str = cmp_modes[1].toStr();
        try self.body.printLine("cmp {s}, {s}, {s}, {s}", .{try self.getValueName(&lhs_v), cmp_str, cmp_str, try self.getValueName(&rhs_v)});
        // TODO: index into value with .xy
        // TODO: fix "error: invalid register: cmp"
        try self.body.printLine("mov {s}, cmp.xy", .{try self.getValueName(&value)});
    }

    pub fn createBranch(self: *Builder, dst: u32) !void {
        // TODO: check if this is correct
        try self.body.printLine("jmpc ones.x, label{}", .{dst});
    }

    // TODO: implement other branch instructions

    // TODO: implement some of the harder std functions as well
    pub fn createStdCall(self: *Builder, result: u32, ty: u32, std_function: base.StdFunction, arguments: []const u32) !void {
        const type_v = self.type_map.get(ty).?;
        const value = base.Value.init("r", self.getAvailableRegister(), type_v);
        try self.id_map.put(result, value);

        switch (std_function) {
            .floor => {
                const arg_v = self.id_map.get(arguments[0]).?;
                try self.body.printLine("flr {s}, {s}", .{try self.getValueName(&value), try self.getValueName(&arg_v)});
            },
            .radians => {
                var arg_v = self.id_map.get(arguments[0]).?;
                // TODO: move this into a utility function
                if (!arg_v.canBeSrc2()) {
                    const new_arg_v = try self.createTempValue(arg_v.ty);
                    try self.body.printLine("mov {s}, {s}", .{try self.getValueName(&new_arg_v), try self.getValueName(&arg_v)});
                    arg_v = new_arg_v;
                }
                try self.body.printLine("mul {s}, deg_to_rad, {s}", .{try self.getValueName(&value), try self.getValueName(&arg_v)});
            },
            .degrees => {
                var arg_v = self.id_map.get(arguments[0]).?;
                if (!arg_v.canBeSrc2()) {
                    const new_arg_v = try self.createTempValue(arg_v.ty);
                    try self.body.printLine("mov {s}, {s}", .{try self.getValueName(&new_arg_v), try self.getValueName(&arg_v)});
                    arg_v = new_arg_v;
                }
                try self.body.printLine("mul {s}, rad_to_deg, {s}", .{try self.getValueName(&value), try self.getValueName(&arg_v)});
            },
            .exp2 => {
                const arg_v = self.id_map.get(arguments[0]).?;
                try self.body.printLine("ex2 {s}, {s}", .{try self.getValueName(&value), try self.getValueName(&arg_v)});
            },
            .log2 => {
                const arg_v = self.id_map.get(arguments[0]).?;
                try self.body.printLine("lg2 {s}, {s}", .{try self.getValueName(&value), try self.getValueName(&arg_v)});
            },
            .sqrt => {
                const arg_v = self.id_map.get(arguments[0]).?;
                try self.body.printLine("rsq {s}, {s}", .{try self.getValueName(&value), try self.getValueName(&arg_v)});
                try self.body.printLine("rcp {s}, {s}", .{try self.getValueName(&value), try self.getValueName(&value)});
            },
            .inverse_sqrt => {
                const arg_v = self.id_map.get(arguments[0]).?;
                try self.body.printLine("rsq {s}, {s}", .{try self.getValueName(&value), try self.getValueName(&arg_v)});
            },
            .min => {
                var arg1_v = self.id_map.get(arguments[0]).?;
                var arg2_v = self.id_map.get(arguments[1]).?;
                _ = try self.swapIfNeeded(&arg1_v, &arg2_v);
                try self.body.printLine("min {s}, {s}, {s}", .{try self.getValueName(&value), try self.getValueName(&arg1_v), try self.getValueName(&arg2_v)});
            },
            .max => {
                var arg1_v = self.id_map.get(arguments[0]).?;
                var arg2_v = self.id_map.get(arguments[1]).?;
                _ = try self.swapIfNeeded(&arg1_v, &arg2_v);
                try self.body.printLine("max {s}, {s}, {s}", .{try self.getValueName(&value), try self.getValueName(&arg1_v), try self.getValueName(&arg2_v)});
            },
            .clamp => {
                var arg1_v = self.id_map.get(arguments[0]).?;
                var arg2_v = self.id_map.get(arguments[1]).?;
                const arg3_v = self.id_map.get(arguments[2]).?;
                _ = try self.swapIfNeeded(&arg1_v, &arg2_v);
                try self.body.printLine("max {s}, {s}, {s}", .{try self.getValueName(&value), try self.getValueName(&arg1_v), try self.getValueName(&arg2_v)});
                try self.body.printLine("min {s}, {s}, {s}", .{try self.getValueName(&value), try self.getValueName(&arg3_v), try self.getValueName(&value)});
            },
            .mix => {
                var arg1_v = self.id_map.get(arguments[0]).?;
                var arg2_v = self.id_map.get(arguments[1]).?;
                const arg3_v = self.id_map.get(arguments[2]).?;
                _ = try self.swapIfNeeded(&arg1_v, &arg2_v);
                const temp = try self.createTempValue(type_v);

                // value = arg1 * (1 - arg3)
                try self.body.printLine("add {s}, ones, -{s}", .{try self.getValueName(&temp), try self.getValueName(&arg3_v)});
                try self.body.printLine("mul {s}, {s}, {s}", .{try self.getValueName(&value), try self.getValueName(&arg1_v), try self.getValueName(&temp)});

                // value = value + arg2 * arg3
                try self.body.printLine("mul {s}, {s}, {s}", .{try self.getValueName(&temp), try self.getValueName(&arg2_v), try self.getValueName(&arg3_v)});
                try self.body.printLine("add {s}, {s}, {s}", .{try self.getValueName(&value), try self.getValueName(&value), try self.getValueName(&temp)});
            },
            .fma => {
                var arg1_v = self.id_map.get(arguments[0]).?;
                var arg2_v = self.id_map.get(arguments[1]).?;
                const arg3_v = self.id_map.get(arguments[2]).?;
                _ = try self.swapIfNeeded(&arg1_v, &arg2_v);
                try self.body.printLine("mul {s}, {s}, {s}", .{try self.getValueName(&value), try self.getValueName(&arg1_v), try self.getValueName(&arg2_v)});
                try self.body.printLine("min {s}, {s}, {s}", .{try self.getValueName(&value), try self.getValueName(&arg3_v), try self.getValueName(&value)});
            },
            // TODO: implement the rest
            else => {
                try std.debug.panic("{} not implemented\n", .{std_function});
            }
        }
    }
};
