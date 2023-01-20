const std = @import("std");
const AnsiBuffer = @import("ansi_buffer.zig").AnsiBuffer;
const Box = @import("box.zig").Box;

//
pub const SBModel = struct {
    const Self = @This();

    isEmptyFn: *const fn (self: *Self) bool,
    lengthFn: *const fn (self: *Self) usize,
    itemsFn: *const fn (self: *Self) [][]const u8,
    orderedRemoveFn: *const fn (self: *Self, index: usize) void,

    fn isEmpty(self: *Self) bool {
        return self.isEmptyFn(self);
    }
    fn length(self: *Self) usize {
        return self.lengthFn(self);
    }
    fn items(self: *Self) [][]const u8 {
        return self.itemsFn(self);
    }
    fn orderedRemove(self: *Self, index: usize) void {
        self.orderedRemoveFn(self, index);
    }
};

// implements SBModel
pub const StringSliceModel = struct {
    const Self = @This();
    sb_model: SBModel,
    str_slice: [][]const u8,

    pub fn init(str_slice: [][]const u8) Self {
        return Self{
            .sb_model = .{
                .isEmptyFn = isEmpty,
                .lengthFn = length,
                .itemsFn = items,
                .orderedRemoveFn = orderedRemove,
            },
            .str_slice = str_slice,
        };
    }
    pub fn isEmpty(model: *SBModel) bool {
        const self = @fieldParentPtr(Self, "sb_model", model);
        return self.str_slice.len <= 0;
    }
    pub fn length(model: *SBModel) usize {
        const self = @fieldParentPtr(Self, "sb_model", model);
        return self.str_slice.len;
    }
    pub fn items(model: *SBModel) [][]const u8 {
        const self = @fieldParentPtr(Self, "sb_model", model);
        return self.str_slice;
    }
    pub fn orderedRemove(model: *SBModel, index: usize) void {
        _ = model;
        _ = index;
        std.debug.panic("Not implemented!", .{});
    }
};

pub const SelectBox = struct {
    const Self = @This();

    box: Box,
    model: *SBModel,
    empty_text: []const u8,
    selected: usize,
    key_up: u8,
    key_down: u8,

    pub fn init(top: u16, left: u16, width: u16, model: *SBModel, comptime key_up: u8, comptime key_down: u8) Self {
        return Self{
            .box = Box{
                .top = top,
                .left = left,
                .width = width,
                .height = @intCast(u16, model.length()) + 4,
                .title = null,
            },
            .model = model,
            .empty_text = "empty",
            .selected = 0,
            .key_up = key_up,
            .key_down = key_down,
        };
    }

    pub fn setEmptyText(self: *Self, text: []const u8) void {
        self.empty_text = text;
    }

    pub fn isEmpty(self: Self) bool {
        return self.model.isEmpty();
    }

    pub fn deleteSelected(self: *Self) void {
        if (self.isEmpty()) return;
        const num_items = self.model.length();
        _ = self.model.orderedRemove(self.selected);
        if (self.selected >= num_items - 1 and self.selected != 0) {
            self.selected -= 1;
        }
    }

    pub fn draw(self: Self, stdout: anytype) !void {
        var buf = AnsiBuffer(256).init();
        try self.box.draw(stdout);

        if (self.isEmpty()) {
            buf.cursorPos(@intCast(u16, self.box.top + 2), self.box.left + 1);
            _ = try stdout.write(buf.toSlice());
            _ = try stdout.write(self.empty_text);
        } else for (self.model.items()) |line, i| {
            buf.cursorPos(@intCast(u16, self.box.top + i + 2), self.box.left + 1);
            if (i == self.selected) {
                buf.setBackground(4);
            }
            _ = try stdout.write(buf.toSlice());
            if (line.len > self.box.width - 2) {
                _ = try stdout.write(line[0 .. self.box.width - 2]);
            } else {
                _ = try stdout.write(line);
            }
            if (i == self.selected) {
                buf.reset();
                buf.setDefault();
                _ = try stdout.write(buf.toSlice());
            }
            buf.reset();
        }
    }

    pub fn onKeyDown(self: *Self, ch: u8, stdout: anytype) !void {
        if (self.isEmpty()) return;

        const num_items = self.model.length();

        if (ch == self.key_down) {
            if (self.selected == num_items - 1) {
                self.selected = 0;
            } else {
                self.selected += 1;
            }
            try self.draw(stdout);
        } else if (ch == self.key_up) {
            if (self.selected > 0) {
                self.selected -= 1;
            } else {
                self.selected = num_items - 1;
            }
            try self.draw(stdout);
        }
    }
};
