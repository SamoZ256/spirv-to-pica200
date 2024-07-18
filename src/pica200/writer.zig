const std = @import("std");

pub const Writer = struct {
    arr: std.ArrayList(u8),
    in_scope: bool,

    pub fn init(allocator: std.mem.Allocator) Writer {
        var self: @This() = undefined;
        self.arr = std.ArrayList(u8).init(allocator);
        self.in_scope = false;

        return self;
    }

    pub fn deinit(self: *Writer) void {
        self.arr.deinit();
    }

    pub fn printLine(self: *Writer, comptime fmt: []const u8, args: anytype) !void {
        if (self.in_scope) {
            _ = try self.arr.writer().write("    ");
        }
        try self.arr.writer().print(fmt, args);
        _ = try self.arr.writer().write("\n");
    }

    pub fn printLineScopeIgnored(self: *Writer, comptime fmt: []const u8, args: anytype) !void {
        const was_in_scope = self.in_scope;
        self.in_scope = false;
        try self.printLine(fmt, args);
        self.in_scope = was_in_scope;
    }

    pub fn enterScope(self: *Writer, comptime str: []const u8) !void {
        _ = try self.arr.writer().print("{s}\n", .{str});
        self.in_scope = true;
    }

    pub fn leaveScope(self: *Writer, comptime str: []const u8) !void {
        _ = try self.arr.writer().print("{s}\n", .{str});
        self.in_scope = false;
    }
};
