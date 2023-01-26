const std = @import("std");
const git2 = @import("git2.zig");
const select_box = @import("select_box.zig");

const Allocator = std.mem.Allocator;
const AnsiBuffer = @import("ansi_buffer.zig").AnsiBuffer;
const AnsiTerminal = @import("ansi_terminal.zig").AnsiTerminal;
const StringArrayList = std.ArrayList([]const u8);
const SelectBox = select_box.SelectBox;
const StringSliceModel = select_box.StringSliceModel;

const KEY_BIND = @import("key_bind.zig");

pub fn main() !u8 {
    const allocator = std.heap.c_allocator;

    try git2.init();
    defer git2.deinit();

    var term = try AnsiTerminal.init();
    defer term.deinit();

    var app = App.init(allocator, &term);
    try app.open();
    defer app.deinit();
    try app.eventLoop();
    return app.exit_code;
}

const App = struct {
    const Self = @This();
    const Focus = enum { MAIN_SB, BRANCH_SB };

    allocator: Allocator,
    stderr: std.fs.File,
    repo: git2.GitRepo,
    wt_list: WorktreeList,
    main_sb: SelectBox,
    term: *AnsiTerminal,
    focus: Focus,
    branch_sb: ?SelectBox,
    branch_list: ?[][]const u8,
    br_sb_model: ?StringSliceModel,
    exit_code: u8 = 1,

    fn init(allocator: Allocator, term: *AnsiTerminal) App {
        return Self{
            .allocator = allocator,
            .stderr = std.io.getStdErr(),
            .repo = git2.GitRepo{ .allocator = allocator },
            .wt_list = undefined, // see open()
            .main_sb = undefined, // see open()
            .term = term,
            .focus = .MAIN_SB,
            .branch_sb = null,
            .branch_list = null,
            .br_sb_model = null,
        };
    }

    // two step initialisation: I cannot figure our how to do everything in init()
    fn open(self: *Self) !void {
        try self.repo.open(".");
        self.wt_list = try WorktreeList.init(self.allocator, &self.repo);
        const width = @intCast(u16, self.term.size.width - 40);
        self.main_sb = SelectBox.init(10, 20, width, self.wt_list.asSBModel(), KEY_BIND.UP, KEY_BIND.DOWN);
        self.main_sb.box.setTitle("Select git worktree");
        self.main_sb.setEmptyText("No worktrees found in this repository.");

        // change CWD so it's possible to deleted it
        var repo_dir = try std.fs.openDirAbsolute(self.repo.path.?, .{});
        defer repo_dir.close();
        try repo_dir.setAsCwd();
    }

    fn deinit(self: *Self) void {
        self.wt_list.deinit();
        if (self.branch_list) |branch_list| {
            self.allocator.free(branch_list);
            self.branch_list = null;
        }
        self.repo.close();
    }

    fn eventLoop(self: *Self) !void {
        try self.main_sb.draw(self.term.stdout);

        var buf: [32]u8 = undefined;
        while (true) {
            var bread = try self.term.read(&buf);
            //try self.term.stdout.print("{} {x} {x} {x}\n", .{bread, buf[0], buf[1], buf[2]});

            if (buf[0] == 0x1b) {
                if (bread == 1) {
                    // ESC acts like QUIT
                    buf[0] = KEY_BIND.QUIT;
                } else {
                    //TODO parse ESC codes
                }
            }
            switch (self.focus) {
                .MAIN_SB => {
                    const rc = try self.handleMainSb(buf[0]);
                    if (rc == 0) {
                        break;
                    }
                },
                .BRANCH_SB => {
                    const rc = try self.handleBranchSb(buf[0]);
                    if (rc == 0) {
                        self.focus = .MAIN_SB;
                        try self.branch_sb.?.box.clear(self.term.stdout);
                        try self.main_sb.draw(self.term.stdout);
                    }
                },
            }
        }
    }

    fn handleMainSb(self: *Self, key: u8) !u8 {
        try self.main_sb.onKeyDown(key, self.term.stdout);
        switch (key) {
            KEY_BIND.QUIT => {
                return 0;
            },
            KEY_BIND.SELECT1, KEY_BIND.SELECT2 => {
                if (!self.main_sb.isEmpty()) {
                    var split_it = std.mem.split(u8, self.wt_list.str_list.items[self.main_sb.selected], " ");
                    const dir = split_it.first();
                    self.exit_code = try writeTempFile(self.allocator, dir);
                    return 0;
                }
            },
            KEY_BIND.ADD_NEW => {
                self.branch_list = try self.repo.getBranchList(self.allocator, false);
                self.br_sb_model = StringSliceModel.init(self.branch_list.?);
                const width = @intCast(u16, self.term.size.width - 60);
                self.branch_sb = SelectBox.init(12, 30, width, &self.br_sb_model.?.sb_model, KEY_BIND.UP, KEY_BIND.DOWN);
                self.branch_sb.?.box.setTitle("Select git branch to convert to worktree");
                self.branch_sb.?.setEmptyText("No branches found in this repository.");
                try self.branch_sb.?.draw(self.term.stdout);
                self.focus = .BRANCH_SB;
            },
            KEY_BIND.DELETE => {
                if (!self.main_sb.isEmpty()) {
                    const dialog_top = self.main_sb.box.top + self.main_sb.box.height - 2;
                    const dialog_left = self.main_sb.box.left + 2;
                    var wt = self.wt_list.list.items[self.main_sb.selected];
                    if (wt.is_main) {
                        const text = "Main worktree cannot be deleted!";
                        try statusMessage(dialog_top, dialog_left, text, self.term);
                    } else {
                        var text = try std.fmt.allocPrint(self.allocator, "Deleting worktree {s} ... Are you sure? (y/n)", .{wt.name});
                        defer self.allocator.free(text);
                        const yn = try ynDialog(dialog_top, dialog_left, text, self.term);
                        if (yn == 'y') {
                            if (wt.delete()) {
                                self.main_sb.deleteSelected();
                                try self.main_sb.box.clear(self.term.stdout);
                                self.main_sb.box.height -= 1;
                            } else |err| {
                                try self.stderr.writer().print("error {}\n", .{err});
                            }
                        }
                        try self.main_sb.draw(self.term.stdout);
                    }
                }
            },
            else => {},
        }
        return 1;
    }

    fn handleBranchSb(self: *Self, key: u8) !u8 {
        try self.branch_sb.?.onKeyDown(key, self.term.stdout);
        switch (key) {
            KEY_BIND.QUIT => {
                return 0;
            },
            KEY_BIND.SELECT1, KEY_BIND.SELECT2 => {
                if (!self.branch_sb.?.isEmpty()) {
                    const branch_name = self.branch_list.?[self.branch_sb.?.selected];
                    if (self.wt_list.findByBranchName(branch_name)) |_| {
                        const dialog_top = self.branch_sb.?.box.top + self.branch_sb.?.box.height - 2;
                        const dialog_left = self.branch_sb.?.box.left + 2;
                        const text = "This branch is already binded to a worktree.";
                        try statusMessage(dialog_top, dialog_left, text, self.term);
                    } else {
                        var path = try std.fmt.allocPrintZ(self.allocator, "../{s}", .{branch_name});
                        defer self.allocator.free(path);
                        var newwt = try self.repo.addWorktree(branch_name, path);
                        try self.wt_list.appendOne(newwt);
                        self.main_sb.box.height += 1;
                        return 0;
                    }
                }
            },
            else => {},
        }
        return 1;
    }
};

const WorktreeList = struct {
    const Self = @This();

    sb_model: select_box.SBModel,
    list: git2.GitWorktreeArrayList,
    str_list: StringArrayList,
    //arena: std.heap.ArenaAllocator,
    allocator: Allocator,
    max_path_width: usize,

    fn init(allocator: Allocator, repo: *git2.GitRepo) !Self {
        var self = Self{
            .sb_model = .{
                .isEmptyFn = &WorktreeList.isEmpty,
                .lengthFn = &WorktreeList.length,
                .itemsFn = &WorktreeList.items,
                .orderedRemoveFn = &WorktreeList.orderedRemove,
            },
            .str_list = undefined,
            .list = undefined,
            //.arena = std.heap.ArenaAllocator.init(allocator),
            .allocator = allocator,
            .max_path_width = 0,
        };
        //self.allocator = self.arena.allocator();

        self.list = try repo.getWorktreeList(self.allocator);
        self.max_path_width = 0;
        for (self.list.items) |*wt| {
            if (wt.path.len > self.max_path_width) {
                self.max_path_width = wt.path.len;
            }
        }

        self.str_list = try StringArrayList.initCapacity(self.allocator, self.list.items.len * 2);
        for (self.list.items) |*wt| {
            self.str_list.addOneAssumeCapacity().* = try formatWorktree(self.allocator, wt.*, self.max_path_width + 1);
        }
        return self;
    }

    fn deinit(self: *Self) void {
        _ = self;
        // FIXME:
        //self.arena.deinit();
    }

    fn findByBranchName(self: Self, name: []const u8) ?*git2.GitWorktree {
        for (self.list.items) |*wt_item| {
            if (std.mem.eql(u8, wt_item.branch_name, name)) {
                return wt_item;
            }
        }
        return null;
    }

    fn asSBModel(self: *Self) *select_box.SBModel {
        return &self.sb_model;
    }
    fn appendOne(self: *Self, wt: git2.GitWorktree) !void {
        const width = std.math.max(wt.path.len, self.max_path_width + 1);
        const as_text = try formatWorktree(self.allocator, wt, width);
        try self.str_list.append(as_text);
        try self.list.append(wt);
    }

    fn isEmpty(model: *select_box.SBModel) bool {
        const self = @fieldParentPtr(Self, "sb_model", model);
        return self.str_list.items.len <= 0;
    }
    fn length(model: *select_box.SBModel) usize {
        const self = @fieldParentPtr(Self, "sb_model", model);
        return self.str_list.items.len;
    }
    fn items(model: *select_box.SBModel) [][]const u8 {
        const self = @fieldParentPtr(Self, "sb_model", model);
        return self.str_list.items;
    }
    fn orderedRemove(model: *select_box.SBModel, index: usize) void {
        const self = @fieldParentPtr(Self, "sb_model", model);
        _ = self.list.orderedRemove(index);
        _ = self.str_list.orderedRemove(index);
    }
};

fn formatWorktree(allocator: Allocator, wt: git2.GitWorktree, width: usize) ![]const u8 {
    var buf: [1024] u8 = undefined;
    std.mem.copy(u8, &buf, wt.path);
    std.mem.set(u8, buf[wt.path.len..width], ' ');
    return try std.fmt.allocPrint(allocator, "{s} {s} [{s}]\n", .{ buf[0..width], wt.oid_as_str[0..6], wt.branch_name });
}

fn ynDialog(top: u16, left: u16, text: []const u8, term: *AnsiTerminal) !u8 {
    var abuf = AnsiBuffer(1024).init();
    abuf.cursorPos(top, left);
    abuf.concat(text);
    try term.stdout.writeAll(abuf.toSlice());
    var kbuf: [32]u8 = undefined;
    while (true) {
        var bread = try term.stdin.read(&kbuf);
        if (bread == 1 and (kbuf[0] == 'y' or kbuf[0] == 'n')) {
            return kbuf[0];
        }
    }
}

fn statusMessage(top: u16, left: u16, text: []const u8, term: *AnsiTerminal) !void {
    var abuf = AnsiBuffer(1024).init();
    abuf.cursorPos(top, left);
    abuf.concat(text);
    try term.stdout.writeAll(abuf.toSlice());
}

fn dicoverTempPath(allocator: Allocator) ![]const u8 {
    if (std.process.hasEnvVarConstant("TMPDIR")) {
        return try std.process.getEnvVarOwned(allocator, "TMPDIR");
    } else
    if (std.process.hasEnvVarConstant("TEMP")) {
        return try std.process.getEnvVarOwned(allocator, "TEMP");
    } else
    if (std.process.hasEnvVarConstant("TMP")) {
        return try std.process.getEnvVarOwned(allocator, "TMP");
    }
    return error.ENOTFOUND;
}

fn writeTempFile(allocator: Allocator, text: []const u8) !u8 {
    const temp_path = try dicoverTempPath(allocator);
    defer allocator.free(temp_path);
    const temp_dir = try std.fs.openDirAbsolute(temp_path, .{});
    try temp_dir.writeFile("zig-worktree.path", text);
    return 0;
}
