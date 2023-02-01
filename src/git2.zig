const c = @cImport({
    @cInclude("git2.h");
});
const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

pub const GitError = error{
    ERROR, // Generic error
    ENOTFOUND, // Requested object could not be found
    EEXISTS, // Object exists preventing operation
    EAMBIGUOUS, // More than one object matches
    EBUFS, // Output buffer too short to hold data
    EBAREREPO, // Operation not allowed on bare repository
    EUNBORNBRANCH, // HEAD refers to branch with no commits
    EUNMERGED, // Merge in progress prevented operation
    ENONFASTFORWARD, // Reference was not fast-forwardable
    EINVALIDSPEC, // Name/ref spec was not in a valid format
    ECONFLICT, // Checkout conflicts prevented operation
    ELOCKED, // Lock file prevented operation
    EMODIFIED, // Reference value does not match expected
    EAUTH, // Authentication error
    ECERTIFICATE, // Server certificate is invalid
    EAPPLIED, // Patch/merge has already been applied
    EPEEL, // The requested peel operation is not possible
    EEOF, // Unexpected EOF
    EINVALID, // Invalid operation or input
    EUNCOMMITTED, // Uncommitted changes in index prevented operation
    EDIRECTORY, // The operation is not valid for a directory
    EMERGECONFLICT, // A merge conflict exists and cannot continue
    PASSTHROUGH, // A user-configured callback refused to act
    ITEROVER, // Signals end of iteration with iterator
    RETRY, // Internal only
    EMISMATCH, // Hashsum mismatch in object
    EINDEXDIRTY, // Unsaved changes in the index would be overwritten
    EAPPLYFAIL, // Patch application failed
    UKNOWN_ERROR,
};

pub const GitWorktree = struct {
    const Self = @This();
    name: []const u8,
    path: []const u8,
    branch_name: []const u8,
    oid_as_str: [16]u8 = undefined,
    wt: ?*c.git_worktree = null,
    ref: ?*c.git_reference = null,


    // pre: self.wt MUST be set
    pub fn init(self: *Self) GitError!void {
        assert(self.wt != null);
        self.name = std.mem.sliceTo(c.git_worktree_name(self.wt), 0);
        self.path = std.mem.sliceTo(c.git_worktree_path(self.wt), 0);
        try self.addBranchNameAndOid();
    }

    // pre: self.ref MUST be set
    pub fn initMain(self: *Self, path: []const u8) GitError!void {
        assert(self.ref != null);
        self.wt = null;
        self.path = path;
        try self.addBranchNameAndOid();
        self.name = self.branch_name;
    }

    pub fn deinit(self: *Self) void {
        c.git_reference_free(self.ref);
        if (self.wt) |wt| {
            c.git_worktree_free(wt);
            self.wt = null;
        }
    }

    pub inline fn isMain(self: Self) bool {
        return self.wt == null;
    }

    pub fn delete(self: *Self) !void {
        try std.fs.deleteTreeAbsolute(self.path);
        const rc = c.git_worktree_prune(self.wt, null);
        try translateError(rc);
    }

    fn addBranchNameAndOid(self: *Self) GitError!void {
        assert(self.ref != null);
        var branch_name: [*c]const u8 = undefined;
        var rc = c.git_branch_name(&branch_name, self.ref);
        try translateError(rc);

        self.branch_name = std.mem.sliceTo(branch_name, 0);
        var oid = c.git_reference_target(self.ref);
        _ = c.git_oid_tostr(&self.oid_as_str, 15, oid);
    }
};

pub const GitWorktreeArrayList = std.ArrayList(GitWorktree);

pub const GitRepo = struct {
    const Self = @This();
    allocator: Allocator,
    repo: ?*c.git_repository = null,
    path: ?[]const u8 = null,

    pub fn open(self: *Self, path: []const u8) (Allocator.Error||GitError)!void {
        var repo: ?*c.git_repository = null;
        var rc = c.git_repository_open(&repo, path.ptr);
        try translateError(rc);
        defer c.git_repository_free(repo); 

        var common_dir = std.mem.sliceTo(c.git_repository_commondir(repo), 0);
        var last = common_dir.len - 1;
        if (common_dir[last] == '/') last -= 1;
        while (common_dir[last] != '/') : (last -= 1) {}

        rc = c.git_repository_open(&self.repo, common_dir);
        try translateError(rc);
        self.path = try self.allocator.dupe(u8, common_dir[0..last]);
    }

    pub fn close(self: *Self) void {
        if (self.repo) |repo| {
            c.git_repository_free(repo); 
        }
        if (self.path) |path| {
            self.allocator.free(path);
        }
    }

    pub fn getWorktreeByName(self: *Self, name: [*c]const u8, wt: *GitWorktree) GitError!void {
        assert(self.repo != null);
        var rc = c.git_worktree_lookup(&wt.wt, self.repo, name);
        try translateError(rc);

        rc = c.git_repository_head_for_worktree(&wt.ref, self.repo, name);
        try translateError(rc);

        return wt.init();
    }

    fn getMainWorktree(self: *Self, wt: *GitWorktree) GitError!void {
        assert(self.repo != null);

        var rc = c.git_repository_head(&wt.ref, self.repo);
        try translateError(rc);

        return wt.initMain(self.path.?);
    }

    pub fn getWorktreeList(self: *Self) (Allocator.Error||GitError)!GitWorktreeArrayList {
        assert(self.repo != null);
        var worktrees: c.git_strarray = undefined;
        var rc = c.git_worktree_list(&worktrees, self.repo);
        try translateError(rc);
        defer _ = c.git_strarray_free(&worktrees);

        var gwal = try GitWorktreeArrayList.initCapacity(self.allocator, (worktrees.count + 4) * 2);

        var wt: * GitWorktree = gwal.addOneAssumeCapacity();
        try self.getMainWorktree(wt);

        if (worktrees.count > 0) {
            var i: usize = 0;
            while (i < worktrees.count) : (i += 1) {
                try self.getWorktreeByName(worktrees.strings[i], gwal.addOneAssumeCapacity());
            }
        }
        return gwal;
    }

    pub fn addWorktree(self: *Self, name: []const u8, branch_name: []const u8, path: []const u8) GitError!GitWorktree {
        assert(self.repo != null);
        var add_opt: c.git_worktree_add_options = undefined;
        add_opt.version = c.GIT_WORKTREE_ADD_OPTIONS_VERSION;
        add_opt.lock = 0;
        var rc = c.git_checkout_options_init(&add_opt.checkout_options, c.GIT_CHECKOUT_OPTIONS_VERSION);
        try translateError(rc);

        rc = c.git_branch_lookup(&add_opt.ref, self.repo, branch_name.ptr, c.GIT_BRANCH_LOCAL);
        try translateError(rc);
        defer c.git_reference_free(add_opt.ref);

        var wt: GitWorktree = GitWorktree{ .name = undefined, .path = undefined, .branch_name = undefined };
        rc = c.git_worktree_add(&wt.wt, self.repo, name.ptr, path.ptr, &add_opt);
        try translateError(rc);

        var oid = c.git_reference_target(add_opt.ref);
        _ = c.git_oid_tostr(&wt.oid_as_str, 15, oid);
        wt.path = std.mem.sliceTo(c.git_worktree_path(wt.wt), 0);
        wt.name = std.mem.sliceTo(c.git_worktree_name(wt.wt), 0);
        wt.branch_name = wt.name;

        return wt;
    }

    pub fn getBranchList(self: *Self, remote: bool) (Allocator.Error||GitError)![][]const u8 {
        assert(self.repo != null);
        const size = try self.getBranchListPriv(null, remote);
        var branch_list = try self.allocator.alloc([]const u8, size);
        _ = try self.getBranchListPriv(branch_list, remote);
        return branch_list;
    }

    fn getBranchListPriv(self: *Self, branch_list: ?[][]const u8, remote: bool) (Allocator.Error||GitError)!usize {
        var branch_it: ?*c.git_branch_iterator = null;
        var rc = c.git_branch_iterator_new(&branch_it, self.repo, if (remote) c.GIT_BRANCH_REMOTE else c.GIT_BRANCH_LOCAL);
        try translateError(rc);

        defer _ = c.git_branch_iterator_free(branch_it);

        var btype: c.git_branch_t = undefined;
        var ref: ?*c.git_reference = null;
        var indx: usize = 0;
        while (c.git_branch_next(&ref, &btype, branch_it) != c.GIT_ITEROVER) {
            defer c.git_reference_free(ref);
            if (branch_list) |list| {
                var branch_name: [*c]const u8 = undefined;
                rc = c.git_branch_name(&branch_name, ref);
                try translateError(rc);

                list[indx] = try self.allocator.dupeZ(u8, std.mem.sliceTo(branch_name, 0));
            }
            indx += 1;
        }
        return indx;
    }

    pub fn checkoutRemoteBranch(self: *Self, remote_branch_name: []const u8, local_branch_name: []const u8) GitError!void {
        var remote_ref: ?*c.git_reference = null;
        var local_ref: ?*c.git_reference = null;

        var rc = c.git_branch_lookup(&remote_ref, self.repo, remote_branch_name.ptr, c.GIT_BRANCH_REMOTE);
        try translateError(rc);
        defer c.git_reference_free(remote_ref);

        // Create local branch -> remote_ref
        const oid = c.git_reference_target(remote_ref);
        var target_commit: ?*c.git_commit = null;
        rc = c.git_commit_lookup(&target_commit, self.repo, oid);
        try translateError(rc);
        defer c.git_commit_free(target_commit);

        rc = c.git_branch_create(&local_ref, self.repo, local_branch_name.ptr, target_commit, 0); 
        if (rc == c.GIT_EEXISTS) {
            rc = c.git_branch_lookup(&local_ref, self.repo, local_branch_name.ptr, c.GIT_BRANCH_LOCAL);
        }
        try translateError(rc);
        defer c.git_reference_free(local_ref);

        // Set tracking
        rc = c.git_branch_set_upstream(local_ref, remote_branch_name.ptr);
        try translateError(rc);
    }
};

pub fn init() GitError!void {
    var rc = c.git_libgit2_init();
    if (rc < 0) {
        try translateError(rc);
    }
}
pub fn deinit() void {
    _ = c.git_libgit2_shutdown();
}

fn translateError(err: c_int) GitError!void {
    return switch (err) {
        c.GIT_OK => {},
        c.GIT_ERROR => GitError.ERROR,
        c.GIT_ENOTFOUND => GitError.ENOTFOUND,
        c.GIT_EEXISTS => GitError.EEXISTS,
        c.GIT_EAMBIGUOUS => GitError.EAMBIGUOUS,
        c.GIT_EBUFS => GitError.EBUFS,
        c.GIT_EBAREREPO => GitError.EBAREREPO,
        c.GIT_EUNBORNBRANCH => GitError.EUNBORNBRANCH,
        c.GIT_EUNMERGED => GitError.EUNMERGED,
        c.GIT_ENONFASTFORWARD => GitError.ENONFASTFORWARD,
        c.GIT_EINVALIDSPEC => GitError.EINVALIDSPEC,
        c.GIT_ECONFLICT => GitError.ECONFLICT,
        c.GIT_ELOCKED => GitError.ELOCKED,
        c.GIT_EMODIFIED => GitError.EMODIFIED,
        c.GIT_EAUTH => GitError.EAUTH,
        c.GIT_ECERTIFICATE => GitError.ECERTIFICATE,
        c.GIT_EAPPLIED => GitError.EAPPLIED,
        c.GIT_EPEEL => GitError.EPEEL,
        c.GIT_EEOF => GitError.EEOF,
        c.GIT_EINVALID => GitError.EINVALID,
        c.GIT_EUNCOMMITTED => GitError.EUNCOMMITTED,
        c.GIT_EDIRECTORY => GitError.EDIRECTORY,
        c.GIT_EMERGECONFLICT => GitError.EMERGECONFLICT,
        c.GIT_PASSTHROUGH => GitError.PASSTHROUGH,
        c.GIT_ITEROVER => GitError.ITEROVER,
        c.GIT_RETRY => GitError.RETRY,
        c.GIT_EMISMATCH => GitError.EMISMATCH,
        c.GIT_EINDEXDIRTY => GitError.EINDEXDIRTY,
        c.GIT_EAPPLYFAIL => GitError.EAPPLYFAIL,
        else => GitError.UKNOWN_ERROR,
    };
}
