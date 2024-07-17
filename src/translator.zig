const std = @import("std");
const spirv = @import("spirv/mod.zig");
const pica200 = @import("pica200/mod.zig");

fn toPica200StorageClass(storage_class: spirv.headers.StorageClass) pica200.builder.StorageClass {
    return switch (storage_class) {
        .Input => pica200.builder.StorageClass.Input,
        .Output => pica200.builder.StorageClass.Output,
        .Uniform, .UniformConstant => pica200.builder.StorageClass.Uniform,
        else => pica200.builder.StorageClass.Function,
    };
}

fn toPica200Decoration(decoration: []const u32) pica200.builder.Decoration {
    return switch (@as(spirv.headers.Decoration, @enumFromInt(decoration[0]))) {
        .Location => .{ .Location = decoration[1] },
        .BuiltIn => blk: {
            break :blk switch (@as(spirv.headers.BuiltIn, @enumFromInt(decoration[1]))) {
                .Position => .{ .Position = {} },
                else => .{ .None = {} },
            };
        },
        else => .{ .None = {} },
    };
}

pub const Translator = struct {
    spirv_reader: spirv.reader.Reader,
    pica200_builder: pica200.builder.Builder,

    pub fn init(allocator: std.mem.Allocator, spv: []const u32) Translator {
        var self: Translator = undefined;
        self.spirv_reader = spirv.reader.Reader.init(spv);
        self.pica200_builder = pica200.builder.Builder.init(allocator);

        return self;
    }

    pub fn deinit(self: *Translator) void {
        self.pica200_builder.deinit();
    }

    pub fn translate(self: *Translator, writer: anytype) !void {
        self.pica200_builder.initWriters();
        _ = self.spirv_reader.readHeader();
        while (!self.spirv_reader.end()) {
            const instruction = self.spirv_reader.readInstruction();
            try self.translateInstruction(&instruction);
        }
        try self.pica200_builder.write(writer);
        self.pica200_builder.deinitWriters();
    }

    fn translateInstruction(self: *Translator, instruction: *const spirv.reader.Instruction) !void {
        try switch (instruction.opcode) {
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
            .OpNop => self.pica200_builder.createNop(),
            .OpFunction => self.pica200_builder.createMain(),
            .OpFunctionEnd => self.pica200_builder.createEnd(),
            .OpLabel => self.pica200_builder.createLabel(instruction.result_id),
            .OpConstant => self.pica200_builder.createConstant(instruction.result_id, instruction.result_type_id, instruction.operands[0]),
            .OpConstantComposite => self.pica200_builder.createConstantComposite(instruction.result_id, instruction.result_type_id, instruction.operands),
            .OpVariable => self.pica200_builder.createVariable(instruction.result_id, instruction.result_type_id, toPica200StorageClass(@enumFromInt(instruction.operands[0]))),
            .OpLoad => self.pica200_builder.createLoad(instruction.result_id, instruction.operands[0]),
            .OpStore => self.pica200_builder.createStore(instruction.operands[0], instruction.operands[1]),
            .OpCompositeExtract => self.pica200_builder.createAccessChain(instruction.result_id, instruction.operands[0], instruction.operands[1..instruction.operands.len], false),
            .OpAccessChain => self.pica200_builder.createAccessChain(instruction.result_id, instruction.operands[0], instruction.operands[1..instruction.operands.len], true),
            .OpCompositeConstruct => self.pica200_builder.createConstruct(instruction.result_id, instruction.result_type_id, instruction.operands),
            .OpFAdd => self.pica200_builder.createAdd(instruction.result_id, instruction.result_type_id, instruction.operands[0], instruction.operands[1]),
            .OpVectorTimesScalar => self.pica200_builder.createVectorTimesScalar(instruction.result_id, instruction.result_type_id, instruction.operands[0], instruction.operands[1]),
            // Ignored
            .OpCapability => {},
            .OpExtInstImport => {},
            .OpMemoryModel => {},
            .OpEntryPoint => {},
            .OpSource => {},
            .OpReturn => {},
            .OpTypeFunction => {},
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
