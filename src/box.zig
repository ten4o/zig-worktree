const AnsiBuffer = @import("ansi_buffer.zig").AnsiBuffer;
const ansi = @import("ansi_codes.zig");
const BOX = ansi.Boxed(ansi.BOXthick);

pub const Box = struct {
    const Self = @This();
    top: u16,
    left: u16,
    width: u16,
    height: u16,
    title: ?[]const u8,

    pub fn init(top: u16, left: u16, width: u16, height: u16) Self {
        return .{
            .top = top,
            .left = left,
            .width = width,
            .height = height,
            .title = null,
        };
    }

    pub fn setTitle(self: *Self, title: []const u8) void {
        self.title = title;
    }

    pub fn drawLine(s: []const u8, size: usize, stdout: anytype) !void {
        var buf = AnsiBuffer(256).init();
        var chsize = size;
        while (chsize >= 16) {
            buf.fill(s, 16);
            _ = try stdout.write(buf.toSlice());
            chsize -= 16;
            buf.reset();
        }
        if (chsize > 0) {
            buf.fill(s, chsize);
            _ = try stdout.write(buf.toSlice());
        }
    }

    pub fn draw(self: Self, stdout: anytype) !void {
        var buf = AnsiBuffer(256).init();
        buf.cursorPos(self.top, self.left);
        buf.concat(BOX.tl);

        _ = try stdout.write(buf.toSlice());

        var borderWidth: usize = self.width - 2;
        if (self.title) |title| {
            _ = try stdout.write(BOX.teeL);
            _ = try stdout.write(title);
            _ = try stdout.write(BOX.teeR);
            borderWidth -= title.len + 2;
        }

        try drawLine(BOX.hr, borderWidth, stdout);
        _ = try stdout.write(BOX.tr);
        var i: u16 = 1;
        while (i <= self.height - 2) : (i += 1) {
            buf.reset();
            buf.cursorPos(self.top + i, self.left);
            buf.concat(BOX.vt);
            // Repeat (c) CSI (n) b
            buf.concatChar(' ');
            buf.csi();
            buf.concatU16(self.width - 3);
            buf.concatChar('b');
            //buf.cursorPos(self.top + i, self.left + self.width - 1);
            buf.concat(BOX.vt);
            _ = try stdout.write(buf.toSlice());
        }
        buf.reset();
        buf.cursorPos(self.top + i, self.left);
        buf.concat(BOX.bl);
        _ = try stdout.write(buf.toSlice());
        try drawLine(BOX.hr, self.width - 2, stdout);
        _ = try stdout.write(BOX.br);
    }

    pub fn clear(self: Self, stdout: anytype) !void {
        var buf = AnsiBuffer(256).init();
        var i: u16 = 0;
        while (i <= self.height) : (i += 1) {
            buf.reset();
            buf.cursorPos(self.top + i, self.left);
            // Repeat (c) CSI (n) b
            buf.concatChar(' ');
            buf.csi();
            buf.concatU16(self.width);
            buf.concatChar('b');
            _ = try stdout.write(buf.toSlice());
        }
    }
};
