const std = @import("std");
const spirv = @import("spirv/mod.zig");
const pica200 = @import("pica200/mod.zig");

fn toPica200StorageClass(storage_class: spirv.headers.StorageClass) pica200.base.StorageClass {
    return switch (storage_class) {
        .Input => .input,
        .Output => .output,
        .Uniform, .UniformConstant => .uniform,
        else => .function,
    };
}

fn toPica200StdFunction(std_function: u32) pica200.base.StdFunction {
    return switch (std_function) {
        1 => .round,
        2 => .round_even,
        3 => .trunc,
        4 => .abs,
        6 => .sign,
        8 => .floor,
        9 => .ceil,
        10 => .fract,
        11 => .radians,
        12 => .degrees,
        13 => .sin,
        14 => .cos,
        15 => .tan,
        16 => .asin,
        17 => .acos,
        18 => .atan,
        19 => .sinh,
        20 => .cosh,
        21 => .tanh,
        22 => .asinh,
        23 => .acosh,
        24 => .atanh,
        25 => .atan2,
        26 => .pow,
        27 => .exp,
        28 => .log,
        29 => .exp2,
        30 => .log2,
        31 => .sqrt,
        32 => .inverse_sqrt,
        33 => .determinant,
        34 => .matrix_inverse,
        37 => .min,
        40 => .max,
        43 => .clamp,
        46 => .mix,
        48 => .step,
        49 => .smooth_step,
        50 => .fma,
        66 => .length,
        67 => .distance,
        68 => .cross,
        69 => .normalize,
        70 => .face_forward,
        71 => .reflect,
        72 => .refract,
        else => std.debug.panic("unknown std function: {}", .{std_function}),
    };
}

fn toPica200Decoration(decoration: []const u32) pica200.base.Decoration {
    return switch (@as(spirv.headers.Decoration, @enumFromInt(decoration[0]))) {
        .Location => .{ .location = decoration[1] },
        .BuiltIn => blk: {
            break :blk switch (@as(spirv.headers.BuiltIn, @enumFromInt(decoration[1]))) {
                .Position => .{ .position = {} },
                else => .{ .none = {} },
            };
        },
        else => .{ .none = {} },
    };
}

pub const Translator = struct {
    spirv_reader: spirv.reader.Reader,
    pica200_builder: pica200.builder.Builder,

    pub fn init(allocator: std.mem.Allocator, spv: []const u32) !Translator {
        var self: Translator = undefined;
        self.spirv_reader = spirv.reader.Reader.init(allocator, spv);
        self.pica200_builder = try pica200.builder.Builder.init(allocator);

        return self;
    }

    pub fn deinit(self: *Translator) void {
        self.pica200_builder.deinit();
    }

    pub fn translate(self: *Translator, writer: anytype) !void {
        self.spirv_reader.reset();
        try self.spirv_reader.findIdLifetimes();
        self.spirv_reader.reset();

        try self.pica200_builder.initWriters();
        _ = self.spirv_reader.readHeader();
        while (!self.spirv_reader.end()) {
            const instruction = self.spirv_reader.readInstruction();
            try self.translateInstruction(&instruction);
            // Release ids
            self.pica200_builder.releaseTempRegisters();
            for (self.spirv_reader.getIdsToRelease()) |id| {
                self.pica200_builder.releaseId(id);
            }
        }
        try self.pica200_builder.write(writer);
        self.pica200_builder.deinitWriters();
    }

    fn translateInstruction(self: *Translator, instruction: *const spirv.reader.Instruction) !void {
        try switch (instruction.opcode) {
            // Header
            .OpEntryPoint => self.pica200_builder.createEntryPoint(instruction.operands[1]),
            // Decorations
            .OpDecorate => self.pica200_builder.createDecoration(instruction.operands[0], toPica200Decoration(instruction.operands[1..])),
            .OpMemberDecorate => self.pica200_builder.createMemberDecoration(instruction.operands[0], instruction.operands[1], toPica200Decoration(instruction.operands[2..])),
            // Types
            .OpTypeVoid => self.pica200_builder.createVoidType(instruction.result_id),
            .OpTypeBool => self.pica200_builder.createBoolType(instruction.result_id),
            .OpTypeInt => self.pica200_builder.createIntType(instruction.result_id, instruction.operands[1] == 1),
            .OpTypeFloat => self.pica200_builder.createFloatType(instruction.result_id),
            .OpTypeVector => self.pica200_builder.createVectorType(instruction.result_id, instruction.operands[0], instruction.operands[1]),
            .OpTypeMatrix => self.pica200_builder.createMatrixType(instruction.result_id, instruction.operands[0], instruction.operands[1]),
            .OpTypeArray => self.pica200_builder.createArrayType(instruction.result_id, instruction.operands[0], instruction.operands[1]),
            .OpTypeStruct => self.pica200_builder.createStructType(instruction.result_id, instruction.operands),
            .OpTypePointer => self.pica200_builder.createPointerType(instruction.result_id, instruction.operands[1]),
            // Instructions
            .OpFunction => self.pica200_builder.createFunction(instruction.result_id),
            .OpLabel => self.pica200_builder.createLabel(instruction.result_id),
            .OpConstant => self.pica200_builder.createConstant(instruction.result_id, instruction.result_type_id, instruction.operands[0]),
            .OpConstantComposite => self.pica200_builder.createConstantComposite(instruction.result_id, instruction.result_type_id, instruction.operands),
            .OpVariable => self.pica200_builder.createVariable(instruction.result_id, instruction.result_type_id, toPica200StorageClass(@enumFromInt(instruction.operands[0]))),
            .OpNop => self.pica200_builder.createNop(),
            .OpLoad => self.pica200_builder.createLoad(instruction.result_id, instruction.operands[0]),
            .OpStore => self.pica200_builder.createStore(instruction.operands[0], instruction.operands[1]),
            .OpCompositeExtract => self.pica200_builder.createAccessChain(instruction.result_id, instruction.operands[0], instruction.operands[1..instruction.operands.len], false),
            .OpAccessChain => self.pica200_builder.createAccessChain(instruction.result_id, instruction.operands[0], instruction.operands[1..instruction.operands.len], true),
            .OpCompositeConstruct => self.pica200_builder.createConstruct(instruction.result_id, instruction.result_type_id, instruction.operands),
            .OpSelect => self.pica200_builder.createSelect(instruction.result_id, instruction.result_type_id, instruction.operands[0], instruction.operands[1], instruction.operands[2]),
            .OpPhi => self.pica200_builder.createPhi(instruction.result_id, instruction.result_type_id, instruction.operands),
            // TODO: don't ignore this
            .OpSelectionMerge => {},
            // Math
            .OpFAdd => self.pica200_builder.createAdd(instruction.result_id, instruction.result_type_id, instruction.operands[0], instruction.operands[1], 0),
            .OpFSub => self.pica200_builder.createAdd(instruction.result_id, instruction.result_type_id, instruction.operands[0], instruction.operands[1], 1),
            .OpFMul, .OpVectorTimesScalar => self.pica200_builder.createMul(instruction.result_id, instruction.result_type_id, instruction.operands[0], instruction.operands[1], false),
            .OpFDiv => self.pica200_builder.createMul(instruction.result_id, instruction.result_type_id, instruction.operands[0], instruction.operands[1], true),
            // Matrix math
            .OpMatrixTimesMatrix => self.pica200_builder.createMatrixTimesMatrix(instruction.result_id, instruction.result_type_id, instruction.operands[0], instruction.operands[1]),
            .OpMatrixTimesVector => self.pica200_builder.createMatrixTimesVector(instruction.result_id, instruction.result_type_id, instruction.operands[0], instruction.operands[1]),
            // TODO: implement
            .OpMatrixTimesScalar => std.debug.panic("MatrixTimesScalar not implemented\n", .{}),
            // Comparison
            .OpFOrdEqual => self.pica200_builder.createCmp(instruction.result_id, instruction.result_type_id, instruction.operands[0], instruction.operands[1], .equal),
            .OpFOrdNotEqual => self.pica200_builder.createCmp(instruction.result_id, instruction.result_type_id, instruction.operands[0], instruction.operands[1], .not_equal),
            .OpFOrdLessThan => self.pica200_builder.createCmp(instruction.result_id, instruction.result_type_id, instruction.operands[0], instruction.operands[1], .less_than),
            .OpFOrdLessThanEqual => self.pica200_builder.createCmp(instruction.result_id, instruction.result_type_id, instruction.operands[0], instruction.operands[1], .less_equal),
            .OpFOrdGreaterThan => self.pica200_builder.createCmp(instruction.result_id, instruction.result_type_id, instruction.operands[0], instruction.operands[1], .greater_than),
            .OpFOrdGreaterThanEqual => self.pica200_builder.createCmp(instruction.result_id, instruction.result_type_id, instruction.operands[0], instruction.operands[1], .greater_equal),
            // TODO: OpConvertFToU as well?
            .OpConvertFToS => self.pica200_builder.createFloatToInt(instruction.result_id, instruction.result_type_id, instruction.operands[0]),
            // Branches
            .OpBranch => self.pica200_builder.createBranch(instruction.operands[0]),
            .OpBranchConditional => self.pica200_builder.createBranchConditional(instruction.operands[0], instruction.operands[1], instruction.operands[2]),
            // Special
            .OpExtInst => self.pica200_builder.createStdCall(instruction.result_id, instruction.result_type_id, toPica200StdFunction(instruction.operands[1]), instruction.operands[2..]),
            // Ignored
            .OpCapability => {},
            .OpExtInstImport => {},
            .OpMemoryModel => {},
            .OpSource => {},
            .OpFunctionEnd => {},
            // TODO: don't ignore this
            .OpReturn => {},
            .OpTypeFunction => {},
            // TODO: don't ignore this?
            .OpLoopMerge => {},
            // TODO: use these for debugging
            .OpName => {},
            .OpMemberName => {},
            // Invalid
            .OpFunctionCall => std.debug.panic("OpFunctionCall is not supported\n", .{}),
            .OpFunctionParameter => std.debug.panic("OpFunctionParameter is not supported\n", .{}),
            else => |opcode| std.debug.panic("unimplemented instruction {}\n", .{opcode}),
        };
    }
};
