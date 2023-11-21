const std = @import("std");
const AnsiBuffer = @import("ansi_buffer.zig").AnsiBuffer;
const Box = @import("box.zig").Box;
const ansi = @import("ansi_codes.zig");

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
        return .{
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
    selected: usize,
    view_offset: usize,
    view_size: usize,
    empty_text: []const u8,
    key_up: u8 = undefined,
    key_down: u8 = undefined,

    pub fn init(top: u16, left: u16, width: u16, max_height: u16, model: *SBModel) Self {
        var height = max_height - 4;
        if (height > model.length()) {
            height = @intCast(model.length());
        }
        return .{
            .box = .{
                .top = top,
                .left = left,
                .width = width,
                .height = height + 4,
                .title = null,
            },
            .model = model,
            .empty_text = "empty",
            .selected = 0,
            .view_offset = 0,
            .view_size = height,
        };
    }

    pub fn setTitle(self: *Self, text: []const u8) *Self {
        self.box.setTitle(text);
        return self;
    }

    pub fn setEmptyText(self: *Self, text: []const u8) *Self {
        self.empty_text = text;
        return self;
    }

    pub fn setKeys(self: *Self, comptime key_up: u8, comptime key_down: u8) *Self {
        self.key_up = key_up;
        self.key_down = key_down;
        return self;
    }

    pub fn isEmpty(self: Self) bool {
        return self.model.isEmpty();
    }

    pub fn onNewRow(self: *Self) void {
        // TODO: if height too large then don't increase
        self.box.height += 1;
        self.view_size += 1;
    }

    pub fn getSelectedIndex(self: Self) usize {
        return self.selected + self.view_offset;
    }

    pub fn getSelectedItem(self: Self) []const u8 {
        return self.model.items()[self.getSelectedIndex()];
    }

    pub fn deleteSelected(self: *Self) void {
        if (self.isEmpty()) return;
        const num_items = self.model.length();
        _ = self.model.orderedRemove(self.getSelectedIndex());
        if (self.selected >= num_items - 1 and self.selected != 0) {
            self.selected -= 1;
        }
        if (self.box.height - 4 == self.view_size) {
            self.box.height -= 1;
            self.view_size -= 1;
        } else {
            if (self.view_offset > 0) {
                self.view_offset -= 1;
            }
        }
    }

    pub fn draw(self: Self, stdout: anytype) !void {
        var buf = AnsiBuffer(256).init();
        try self.box.draw(stdout);

        if (self.isEmpty()) {
            buf.cursorPos(@intCast(self.box.top + 2), self.box.left + 1);
            _ = try stdout.write(buf.toSlice());
            _ = try stdout.write(self.empty_text);
        } else for (self.model.items()[self.view_offset..(self.view_offset + self.view_size)], 0..) |line, i| {
            buf.cursorPos(@intCast(self.box.top + i + 2), self.box.left + 1);
            if (i == self.selected) {
                buf.setBackground(@intFromEnum(ansi.Color.C256.blue));
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
            if (self.selected == self.view_size - 1) {
                if (self.view_size == num_items or (self.view_offset + self.selected >= num_items - 1)) {
                    self.selected = 0;
                    self.view_offset = 0;
                } else {
                    self.view_offset += 1;
                }
            } else {
                self.selected += 1;
            }
            try self.draw(stdout);
        } else if (ch == self.key_up) {
            if (self.selected > 0) {
                self.selected -= 1;
            } else {
                if (self.view_offset > 0) {
                    self.view_offset -= 1;
                } else {
                    self.view_offset = num_items - self.view_size;
                    self.selected = self.view_size - 1;
                }
            }
            try self.draw(stdout);
        }
    }
};
