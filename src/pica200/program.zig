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

const ValueExport = struct {
    result: u32,
    value: u32,
    result_name: []const u8,
    value_name: []const u8,
};

pub const Block = struct {
    allocator: std.mem.Allocator,
    id: u32,
    instructions: std.ArrayList(Instruction),
    value_exports: std.ArrayList(ValueExport),

    pub fn init(allocator: std.mem.Allocator, id: u32) Block {
        var self: Block = undefined;
        self.allocator = allocator;
        self.id = id;
        self.instructions = std.ArrayList(Instruction).init(allocator);
        self.value_exports = std.ArrayList(ValueExport).init(allocator);

        return self;
    }

    pub fn deinit(self: *Block) void {
        self.value_exports.deinit();
        self.instructions.deinit();
    }

    fn writeInstruction(w: *writer.Writer, indent: *u32, instruction: Instruction) !void {
        if (instruction.opcode == .dot_else or instruction.opcode == .dot_end) {
            indent.* -= 1;
        }
        for (0..indent.*) |_| {
            try w.print("    ", .{});
        }
        if (instruction.opcode == .dot_proc or instruction.opcode == .dot_else or instruction.opcode == .ifc or instruction.opcode == .ifu) {
            indent.* += 1;
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

    pub fn write(self: *const Block, w: *writer.Writer) !void {
        try w.printLine("label{}:", .{self.id});

        var header_instructions = std.ArrayList(Instruction).init(self.allocator);
        defer header_instructions.deinit();

        // First handle value exports
        for (self.value_exports.items) |value_export| {
            var found = false;
            for (self.instructions.items) |*instruction| {
                if (instruction.result == value_export.value) {
                    instruction.result = value_export.result;
                    instruction.operands[0] = value_export.result_name;
                    found = true;
                    break;
                }
            }

            // If not found, we can just use a mov instruction
            if (!found) {
                try header_instructions.append(createInstruction(.mov, value_export.result, .{value_export.result_name, value_export.value_name}));
            }
        }

        var indent: u32 = 1;
        for (header_instructions.items) |instruction| {
            try writeInstruction(w, &indent, instruction);
        }
        for (self.instructions.items) |instruction| {
            try writeInstruction(w, &indent, instruction);
        }
    }

    fn createInstruction(opcode: Opcode, result: u32, operands: anytype) Instruction {
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

        return instruction;
    }

    pub fn addInstruction(self: *Block, opcode: Opcode, result: u32, operands: anytype) !void {
        try self.instructions.append(createInstruction(opcode, result, operands));
    }

    pub fn addValueExport(self: *Block, result: u32, value: u32, result_name: []const u8, value_name: []const u8) !void {
        try self.value_exports.append(.{ .result = result, .value = value, .result_name = result_name, .value_name = value_name });
    }
};

pub const Function = struct {
    allocator: std.mem.Allocator,
    id: u32,
    blocks: std.AutoHashMap(u32, Block),
    active_block: u32,

    pub fn init(allocator: std.mem.Allocator, id: u32) Function {
        var self: Function = undefined;
        self.allocator = allocator;
        self.id = id;
        self.blocks = std.AutoHashMap(u32, Block).init(allocator);
        self.active_block = 0;

        return self;
    }

    pub fn deinit(self: *Function) void {
        var it = self.blocks.iterator();
        while (it.next()) |i| {
            i.value_ptr.deinit();
        }
        self.blocks.deinit();
    }

    pub fn write(self: *const Function, w: *writer.Writer) !void {
        try w.printLine(".proc func{}", .{self.id});
        var it = self.blocks.iterator();
        while (it.next()) |i| {
            try i.value_ptr.write(w);
        }
        try w.printLine(".end", .{});
    }

    pub fn getBlock(self: *Function, id: u32) !*Block {
        const result = try self.blocks.getOrPut(id);
        if (!result.found_existing) {
            result.value_ptr.* = Block.init(self.allocator, id);
        }

        return result.value_ptr;
    }

    pub fn addInstruction(self: *Function, opcode: Opcode, result: u32, operands: anytype) !void {
        try self.blocks.getPtr(self.active_block).?.addInstruction(opcode, result, operands);
    }
};

pub const ProgramWriter = struct {
    allocator: std.mem.Allocator,
    functions: std.AutoHashMap(u32, Function),
    active_function: u32,

    pub fn init(allocator: std.mem.Allocator) ProgramWriter {
        var self: ProgramWriter = undefined;
        self.allocator = allocator;
        self.functions = std.AutoHashMap(u32, Function).init(allocator);
        self.active_function = 0;

        return self;
    }

    pub fn deinit(self: *ProgramWriter) void {
        var it = self.functions.iterator();
        while (it.next()) |i| {
            i.value_ptr.deinit();
        }
        self.functions.deinit();
    }

    pub fn write(self: *const ProgramWriter, w: *writer.Writer) !void {
        var it = self.functions.iterator();
        while (it.next()) |i| {
            try i.value_ptr.write(w);
        }
    }

    pub fn getFunction(self: *ProgramWriter, id: u32) !*Function {
        const result = try self.functions.getOrPut(id);
        if (!result.found_existing) {
            result.value_ptr.* = Function.init(self.allocator, id);
        }

        return result.value_ptr;
    }

    pub fn getActiveFunction(self: *ProgramWriter) ?*Function {
        return self.functions.getPtr(self.active_function);
    }

    pub fn addInstruction(self: *ProgramWriter, opcode: Opcode, result: u32, operands: anytype) !void {
        try self.functions.getPtr(self.active_function).?.addInstruction(opcode, result, operands);
    }
};
