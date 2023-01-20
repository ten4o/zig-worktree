## Git Worktree in Zig

This is a toy project that I play with. Its main purpose is to help me learn [Zig](https://ziglang.org/). I also needed a simple git worktree tool.

I's been tried and somewhat works in Linux, MacOS and Windows 10.

To build it you need [libgit2](https://github.com/libgit2/libgit2).
 - on Linux - use you package manager
 - on MacOS - `brew install libgit2`
 - on Windows - I build libgit2 from source and put header files in `./deps/include/` and lib file in `./deps/lib/`

Key bindings are hard-coded in the source:
 - `k` - up
 - `j` - down
 - `a` - add new worktree from local branch
 - `q` or `ESC` - quit/back
 - `Enter` or `Space` - select item

