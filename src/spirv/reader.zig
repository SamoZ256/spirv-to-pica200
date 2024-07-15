const std = @import("std");

pub const Reader = struct {
    spv: []const u32,

    pub fn init(spv: []const u32) Reader {
        var self: Reader = undefined;
        self.spv = spv;
        // HACK
        std.debug.print("SPIRV: {any}\n", .{spv});

        return self;
    }
};
