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
        var lifetime_map = std.AutoHashMap(u32, u32).init(self.allocator);
        defer lifetime_map.deinit();
        var id_remap_map = std.AutoHashMap(u32, u32).init(self.allocator);
        defer id_remap_map.deinit();
        while (!self.end()) {
            try self.writeInstructionIdLifetimes(&lifetime_map, &id_remap_map);
        }
        var it = lifetime_map.iterator();
    	while (it.next()) |i| {
    		try self.id_lifetimes[i.value_ptr.*].append(i.key_ptr.*);
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

    fn writeInstructionIdLifetimes(self: *Reader, lifetime_map: *std.AutoHashMap(u32, u32), id_remap_map: *std.AutoHashMap(u32, u32)) !void {
        // TODO: abstract this away
        const opcode_combined = self.readWord();
        var word_count = (opcode_combined & 0xFFFF0000) >> 16;
        const opcode: headers.Op = @enumFromInt(opcode_combined & 0xFFFF);

        const inst_info = headers.getInstructionInfo(opcode);
        word_count -= 1; // Subtract opcode
        const operands = self.readWords(word_count);
        self.id_lifetimes[self.instruction_counter] = std.ArrayList(u32).init(self.allocator);
        for (0..operands.len) |i| {
            var operand = operands[i];
            const operand_type = inst_info.operands[@min(i, inst_info.operands.len - 1)];
            switch (operand_type) {
                .result_id, .id_ref => {
                    while (true) {
                        const remapped_operand = id_remap_map.get(operand);
                        if (remapped_operand) |remapped_o| {
                            operand = remapped_o;
                        } else {
                            break;
                        }
                    }
                    //std.debug.print("Extending lifetime of {}\n", .{operand});
                    try lifetime_map.put(operand, self.instruction_counter);
                },
                else => {},
            }
        }

        // Every instruction that does not create a new value for the result id must be remapped
        switch (opcode) {
            .OpLoad, .OpCompositeExtract, .OpAccessChain => {
                const id = operands[1];
                const id_ref = operands[2];
                try id_remap_map.put(id, id_ref);
                //std.debug.print("remapping {} to {}\n", .{id, id_ref});
            },
            else => {},
        }

        self.instruction_counter += 1;
    }

    pub fn readInstruction(self: *Reader) Instruction {
        var instruction: Instruction = undefined;

        const opcode_combined = self.readWord();
        var word_count = (opcode_combined & 0xFFFF0000) >> 16;
        instruction.opcode = @enumFromInt(opcode_combined & 0xFFFF);

        const inst_info = headers.getInstructionInfo(instruction.opcode);
        word_count -= 1; // Subtract opcode
        const operands = self.readWords(word_count);
        var operands_begin: u32 = 0;
        for (0..operands.len) |i| {
            const operand = operands[i];
            const operand_type = inst_info.operands[@min(i, inst_info.operands.len - 1)];
            switch (operand_type) {
                .result_type_id => {
                    instruction.result_type_id = operand;
                    operands_begin += 1;
                },
                .result_id => {
                    instruction.result_id = operand;
                    operands_begin += 1;
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
