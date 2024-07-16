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

fn Writer(w_type: type) type {
    return struct {
        w: w_type,
        in_scope: bool,

        pub fn init(w: w_type) @This() {
            var self: @This() = undefined;
            self.w = w;
            self.in_scope = false;

            return self;
        }

        pub fn printLine(self: *@This(), comptime fmt: []const u8, args: anytype) !void {
            if (self.in_scope) {
                _ = try self.w.write("    ");
            }
            try self.w.print(fmt, args);
            _ = try self.w.write("\n");
        }

        pub fn printLineScopeIgnored(self: *@This(), comptime fmt: []const u8, args: anytype) !void {
            const was_in_scope = self.in_scope;
            self.in_scope = false;
            try self.printLine(fmt, args);
            self.in_scope = was_in_scope;
        }

        pub fn enterScope(self: *@This(), comptime str: []const u8) !void {
            _ = try self.w.print("{s}\n", .{str});
            self.in_scope = true;
        }

        pub fn leaveScope(self: *@This(), comptime str: []const u8) !void {
            _ = try self.w.print("{s}\n", .{str});
            self.in_scope = false;
        }
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

    pub fn translate(self: *Translator, w: anytype) !void {
        var writer = Writer(@TypeOf(w)).init(w);

        const header = self.spirv_reader.readHeader();
        try writer.printLine("SPIR-V version: {}", .{header.version});
        while (!self.spirv_reader.end()) {
            const instruction = self.spirv_reader.readInstruction();
            try self.translateInstruction(&writer, &instruction);
        }
    }

    fn translateInstruction(self: *Translator, writer: anytype, instruction: *const spirv.reader.Instruction) !void {
        try switch (instruction.opcode) {
            // Types
            .OpTypeVoid => self.pica200_builder.createVoidType(instruction.result_id),
            .OpTypeBool => self.pica200_builder.createBoolType(instruction.result_id),
            .OpTypeInt => self.pica200_builder.createIntType(instruction.result_id, instruction.operands[1] == 1),
            .OpTypeFloat => self.pica200_builder.createFloatType(instruction.result_id),
            .OpTypeVector => self.pica200_builder.createVectorType(instruction.result_id, instruction.operands[0], instruction.operands[1]),
            .OpTypeMatrix => self.pica200_builder.createMatrixType(instruction.result_id, instruction.operands[0], instruction.operands[1]),
            .OpTypeArray => self.pica200_builder.createArrayType(instruction.result_id, instruction.operands[0], instruction.operands[1]),
            .OpTypeStruct => self.pica200_builder.createStructType(instruction.result_id, instruction.operands),
            // Instructions
            .OpNop => self.pica200_builder.createNop(writer),
            .OpFunction => self.pica200_builder.createMain(writer),
            .OpFunctionEnd => self.pica200_builder.createEnd(writer),
            .OpLabel => self.pica200_builder.createLabel(writer, instruction.result_id),
            .OpConstant => self.pica200_builder.createConstant(writer, instruction.result_id, instruction.result_type_id, instruction.operands[0]),
            .OpVariable => self.pica200_builder.createVariable(writer, instruction.result_id, instruction.result_type_id, toPica200StorageClass(@enumFromInt(instruction.operands[0]))),
            .OpLoad => self.pica200_builder.createLoad(writer, instruction.result_id, instruction.operands[0]),
            .OpStore => self.pica200_builder.createStore(writer, instruction.operands[0], instruction.operands[1]),
            .OpCompositeExtract => self.pica200_builder.createExtract(writer, instruction.result_id, instruction.operands[0], instruction.operands[1..instruction.operands.len]),
            .OpAccessChain => self.pica200_builder.createAccessChain(writer, instruction.result_id, instruction.operands[0], instruction.operands[1..instruction.operands.len]),
            .OpCompositeConstruct => self.pica200_builder.createConstruct(writer, instruction.result_id, instruction.result_type_id, instruction.operands),
            .OpFAdd => self.pica200_builder.createAdd(writer, instruction.result_id, instruction.result_type_id, instruction.operands[0], instruction.operands[1]),
            .OpVectorTimesScalar => self.pica200_builder.createVectorTimesScalar(writer, instruction.result_id, instruction.result_type_id, instruction.operands[0], instruction.operands[1]),
            // Ignored
            .OpCapability => {},
            .OpExtInstImport => {},
            .OpMemoryModel => {},
            .OpEntryPoint => {},
            .OpSource => {},
            .OpReturn => {},
            // TODO: use these for debugging
            .OpName => {},
            .OpMemberName => {},
            else => try writer.printLine("{}", .{instruction.opcode}),
        };
    }
};
