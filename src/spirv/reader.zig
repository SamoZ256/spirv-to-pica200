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
    result_type: u32,
    result: u32,
    operands: []const u32,
};

pub const Reader = struct {
    spv: []const u32,
    word_ptr: usize,

    pub fn init(spv: []const u32) Reader {
        var self: Reader = undefined;
        self.spv = spv;
        self.word_ptr = 5; // Skip header

        return self;
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

    pub fn readInstruction(self: *Reader) Instruction {
        var instruction: Instruction = undefined;

        const opcode_combined = self.readWord();
        var word_count = (opcode_combined & 0xFFFF0000) >> 16;
        instruction.opcode = @enumFromInt(opcode_combined & 0xFFFF);

        const inst_info = headers.getInstructionInfo(instruction.opcode);
        word_count -= 1; // Subtract opcode
        if (inst_info.has_result_type) {
            instruction.result_type = self.readWord();
            word_count -= 1; // Subtract result type
        }
        if (inst_info.has_result) {
            instruction.result = self.readWord();
            word_count -= 1; // Subtract result
        }

        instruction.operands = self.readWords(word_count);

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
