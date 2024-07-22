const std = @import("std");
const headers = @import("headers.zig");

pub const Header = struct {
    magic: u32,
    version: u32,
    generator: u32,
    bound: u32,
    schema: u32,
};

pub const Instruction = struct {
    opcode: headers.Op,
    result_type_id: u32,
    result_id: u32,
    operands: []const u32,
};

pub const Reader = struct {
    allocator: std.mem.Allocator,
    spv: []const u32,
    word_ptr: usize,
    instruction_counter: u32,
    // TODO: make the size dynamic
    id_lifetimes: [1024]std.ArrayList(u32),

    pub fn init(allocator: std.mem.Allocator, spv: []const u32) Reader {
        var self: Reader = undefined;
        self.allocator = allocator;
        self.spv = spv;

        return self;
    }

    pub fn reset(self: *Reader) void {
        self.word_ptr = 5; // Ship header
        self.instruction_counter = 0;
    }

    pub fn findIdLifetimes(self: *Reader) !void {
        while (!self.end()) {
            _ = try self.readInstruction(true);
        }
    }

    pub fn getIdsToRelease(self: *const Reader) []const u32 {
        return self.id_lifetimes[self.instruction_counter - 1].items;
    }

    pub fn readHeader(self: *const Reader) Header {
        var header: Header = undefined;
        header.magic = self.spv[0];
        header.version = self.spv[1];
        header.generator = self.spv[2];
        header.bound = self.spv[3];
        header.schema = self.spv[4];

        return header;
    }

    pub fn readInstruction(self: *Reader, write_id_lifetimes: bool) !Instruction {
        var instruction: Instruction = undefined;

        const opcode_combined = self.readWord();
        var word_count = (opcode_combined & 0xFFFF0000) >> 16;
        instruction.opcode = @enumFromInt(opcode_combined & 0xFFFF);

        const inst_info = headers.getInstructionInfo(instruction.opcode);
        word_count -= 1; // Subtract opcode
        const operands = self.readWords(word_count);
        var operands_begin: u32 = 0;
        var lifetime_array = &self.id_lifetimes[self.instruction_counter];
        if (write_id_lifetimes) {
            lifetime_array.* = std.ArrayList(u32).init(self.allocator);
        }
        for (0..operands.len) |i| {
            const operand = operands[i];
            switch (inst_info.operands[@min(i, inst_info.operands.len - 1)]) {
                .result_type_id => {
                    instruction.result_type_id = operand;
                    operands_begin += 1;
                },
                .result_id => {
                    instruction.result_id = operand;
                    operands_begin += 1;
                },
                .id_ref => {
                    if (write_id_lifetimes) {
                        try lifetime_array.append(operand);
                    }
                },
                else => {},
            }
        }
        instruction.operands = operands[operands_begin..];

        self.instruction_counter += 1;

        return instruction;
    }

    pub fn end(self: *const Reader) bool {
        return self.word_ptr >= self.spv.len;
    }

    fn readWord(self: *Reader) u32 {
        const word = self.spv[self.word_ptr];
        self.word_ptr += 1;

        return word;
    }

    fn readWords(self: *Reader, count: u32) []const u32 {
        const words = self.spv[self.word_ptr..self.word_ptr + count];
        self.word_ptr += count;

        return words;
    }
};
