const std = @import("std");
const spirv = @import("spirv/mod.zig");
const pica200 = @import("pica200/mod.zig");

pub const Translator = struct {
    spirv_reader: spirv.reader.Reader,
    pica200_builder: pica200.builder.Builder,

    pub fn init(spv: []const u32) Translator {
        var self: Translator = undefined;
        self.spirv_reader = spirv.reader.Reader.init(spv);
        self.pica200_builder = pica200.builder.Builder.init();

        return self;
    }

    // TODO: use the writer
    pub fn translate(self: *Translator, _: anytype) !void {
        const header = self.spirv_reader.readHeader();
        std.debug.print("SPIR-V version: {}\n", .{header.version});
        while (!self.spirv_reader.end()) {
            const instruction = self.spirv_reader.readInstruction();
            std.debug.print("Instruction: {}\n", .{instruction.opcode});
        }
    }
};
