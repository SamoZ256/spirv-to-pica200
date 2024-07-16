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
            defer self.in_scope = self.in_scope;
            self.in_scope = false;
            try self.printLine(fmt, args);
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

    // TODO: use the writer
    pub fn translate(self: *Translator, w: anytype) !void {
        var writer = Writer(@TypeOf(w)).init(w);

        const header = self.spirv_reader.readHeader();
        try writer.printLine("SPIR-V version: {}", .{header.version});
        while (!self.spirv_reader.end()) {
            const instruction = self.spirv_reader.readInstruction();
            try self.translateInstruction(&writer, &instruction);
        }
    }

    // TODO: use the writer
    fn translateInstruction(self: *Translator, writer: anytype, instruction: *const spirv.reader.Instruction) !void {
        try switch (instruction.opcode) {
            .OpNop => self.pica200_builder.CreateNop(writer),
            .OpFunction => self.pica200_builder.CreateFunction(writer),
            .OpFunctionEnd => self.pica200_builder.CreateFunctionEnd(writer),
            .OpLabel => self.pica200_builder.CreateLabel(writer, instruction.result_id),
            .OpVariable => self.pica200_builder.CreateVariable(writer, instruction.result_id, instruction.result_type_id, toPica200StorageClass(@enumFromInt(instruction.operands[0]))),
            .OpCompositeExtract => self.pica200_builder.CreateCompositeExtract(writer, instruction.result_id, instruction.operands[0], instruction.operands[1..(instruction.operands.len - 1)]),
            else => try writer.printLine("{}", .{instruction.opcode}),
        };
    }
};
