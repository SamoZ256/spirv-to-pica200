const std = @import("std");
usingnamespace @import("headers.zig");

pub const Header = struct {
    magic: u32,
    version: u32,
    generator: u32,
    bound: u32,
    schema: u32,
};

//pub const Instruction = struct {
//    opcode: u16,
//    operands: []const u32,
//};

pub const Reader = struct {
    spv: []const u32,
    word_ptr: usize,

    pub fn init(spv: []const u32) Reader {
        var self: Reader = undefined;
        self.spv = spv;
        self.word_ptr = 5; // Skip header
        // HACK
        std.debug.print("SPIRV: {any}\n", .{spv});

        return self;
    }

    pub fn readHeader(self: *Reader) Header {
        var header: Header = undefined;
        header.magic = self.spv[0];
        header.version = self.spv[1];
        header.generator = self.spv[2];
        header.bound = self.spv[3];
        header.schema = self.spv[4];

        return header;
    }

    // TODO: uncomment
    //pub fn readInstruction(self: *const Reader) Instruction {
    //    var instruction: Instruction = Instruction.init();

    //    const opcode = self.readWord();
    //    const word_count = (opcode & 0xFFFF0000) >> 16;
    //    const opcode_enum = opcode & 0xFFFF;

    //    ;

    //    for (0..world_count - 1) |i| {
    //        const word = self.readWord();
    //    }

    //    return instruction;
    //}

    pub fn end(self: *const Reader) bool {
        return self.word_ptr >= self.spv.len;
    }

    fn readWord(self: *const Reader) u32 {
        const word = self.spv[self.word_ptr];
        self.word_ptr += 1;

        return word;
    }
};
