const std = @import("std");
const spirv = @import("spirv/mod.zig");
const pica200 = @import("pica200/mod.zig");

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

    pub fn init(spv: []const u32) Translator {
        var self: Translator = undefined;
        self.spirv_reader = spirv.reader.Reader.init(spv);
        self.pica200_builder = pica200.builder.Builder.init();

        return self;
    }

    // TODO: use the writer
    pub fn translate(self: *Translator, w: anytype) !void {
        var writer = Writer(@TypeOf(w)).init(w);

        const header = self.spirv_reader.readHeader();
        try writer.printLine("SPIR-V version: {}", .{header.version});
        while (!self.spirv_reader.end()) {
            const instruction = self.spirv_reader.readInstruction();
            try writer.printLine("Instruction: {}", .{instruction.opcode});
            try self.translateInstruction(&writer, &instruction);
        }
    }

    // TODO: use the writer
    fn translateInstruction(_: *Translator, writer: anytype, instruction: *const spirv.reader.Instruction) !void {
        try switch (instruction.opcode) {
            .OpNop => writer.printLine("nop", .{}),
            .OpFunction => writer.enterScope(".proc main"),
            .OpFunctionEnd => writer.leaveScope(".end"),
            else => {},
        };
    }
};
