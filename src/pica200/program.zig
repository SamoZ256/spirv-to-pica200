const std = @import("std");
const base = @import("base.zig");
const writer = @import("writer.zig");

const Opcode = enum {
    nop,
    end,
    emit,
    setemit,
    add,
    dp3,
    dp4,
    dph,
    dst,
    mul,
    sge,
    slt,
    max,
    min,
    ex2,
    lg2,
    litp,
    flr,
    rcp,
    rsq,
    mov,
    mova,
    cmp,
    call,
    for_,
    break_,
    breakc,
    callc,
    ifc,
    jmpc,
    callu,
    ifu,
    jmpu,
    mad,

    dot_proc,
    dot_else,
    dot_end,

    pub fn toStr(self: Opcode) []const u8 {
        return switch (self) {
            .nop => "nop",
            .end => "end",
            .emit => "emit",
            .setemit => "setemit",
            .add => "add",
            .dp3 => "dp3",
            .dp4 => "dp4",
            .dph => "dph",
            .dst => "dst",
            .mul => "mul",
            .sge => "sge",
            .slt => "slt",
            .max => "max",
            .min => "min",
            .ex2 => "ex2",
            .lg2 => "lg2",
            .litp => "litp",
            .flr => "flr",
            .rcp => "rcp",
            .rsq => "rsq",
            .mov => "mov",
            .mova => "mova",
            .cmp => "cmp",
            .call => "call",
            .for_ => "for",
            .break_ => "break",
            .breakc => "breakc",
            .callc => "callc",
            .ifc => "ifc",
            .jmpc => "jmpc",
            .callu => "callu",
            .ifu => "ifu",
            .jmpu => "jmpu",
            .mad => "mad",
            .dot_proc => ".proc",
            .dot_else => ".else",
            .dot_end => ".end",
        };
    }
};

const Instruction = struct {
    opcode: Opcode,
    result: u32,
    operands: [4][]const u8,
    operand_count: usize,
};

pub const Block = struct {
    id: u32,
    instructions: std.ArrayList(Instruction),

    pub fn init(allocator: std.mem.Allocator, id: u32) Block {
        var self: Block = undefined;
        self.id = id;
        self.instructions = std.ArrayList(Instruction).init(allocator);

        return self;
    }

    pub fn deinit(self: *Block) void {
        self.instructions.deinit();
    }

    pub fn write(self: *const Block, w: *writer.Writer) !void {
        try w.printLine("label{}:", .{self.id});

        var indent: u32 = 1;
        for (self.instructions.items) |instruction| {
            if (instruction.opcode == .dot_else or instruction.opcode == .dot_end) {
                indent -= 1;
            }
            for (0..indent) |_| {
                try w.print("    ", .{});
            }
            if (instruction.opcode == .dot_proc or instruction.opcode == .dot_else or instruction.opcode == .ifc or instruction.opcode == .ifu) {
                indent += 1;
            }

            // Opcode
            const opcode_str = instruction.opcode.toStr();
            try w.print("{s}", .{opcode_str});

            // Operands
            for (0..instruction.operand_count) |i| {
                if (i != 0) {
                    try w.print(",", .{});
                }
                try w.print(" {s}", .{instruction.operands[i]});
            }
            try w.print("\n", .{});
        }
    }

    pub fn addInstruction(self: *Block, opcode: Opcode, result: u32, operands: anytype) !void {
        var instruction: Instruction = undefined;
        instruction.opcode = opcode;
        instruction.result = result;
        //for (0..4) |i| {
        //    if (i < operands.len) {
        //        instruction.operands[i] = operands[i];
        //    } else {
        //        instruction.operands[i] = "";
        //    }
        //}
        // HACK
        if (0 < operands.len) {
            instruction.operands[0] = operands[0];
        } else {
            instruction.operands[0] = "";
        }
        if (1 < operands.len) {
            instruction.operands[1] = operands[1];
        } else {
            instruction.operands[1] = "";
        }
        if (2 < operands.len) {
            instruction.operands[2] = operands[2];
        } else {
            instruction.operands[2] = "";
        }
        if (3 < operands.len) {
            instruction.operands[3] = operands[3];
        } else {
            instruction.operands[3] = "";
        }
        instruction.operand_count = operands.len;

        try self.instructions.append(instruction);
    }
};

pub const ProgramWriter = struct {
    allocator: std.mem.Allocator,
    blocks: std.AutoHashMap(u32, Block),
    active_block: u32,

    pub fn init(allocator: std.mem.Allocator) ProgramWriter {
        var self: ProgramWriter = undefined;
        self.allocator = allocator;
        self.blocks = std.AutoHashMap(u32, Block).init(allocator);

        return self;
    }

    pub fn deinit(self: *ProgramWriter) void {
        var it = self.blocks.iterator();
        while (it.next()) |i| {
            i.value_ptr.deinit();
        }
        self.blocks.deinit();
    }

    pub fn write(self: *const ProgramWriter, w: *writer.Writer) !void {
        try w.printLine(".proc main", .{});
        var it = self.blocks.iterator();
        while (it.next()) |i| {
            try i.value_ptr.write(w);
        }
        try w.printLine(".end", .{});
    }

    pub fn addBlock(self: *ProgramWriter, id: u32) !void {
        const block = Block.init(self.allocator, id);
        try self.blocks.put(id, block);
        self.active_block = id;
    }

    pub fn getBlock(self: *ProgramWriter, id: u32) ?*Block {
        return self.blocks.getPtr(id);
    }

    pub fn addInstruction(self: *ProgramWriter, opcode: Opcode, result: u32, operands: anytype) !void {
        try self.blocks.getPtr(self.active_block).?.addInstruction(opcode, result, operands);
    }
};
