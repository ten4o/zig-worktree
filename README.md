## Git Worktree in Zig

This is a toy project that I play with. Its main purpose is to help me learn [Zig](https://ziglang.org/). I also needed a simple git worktree tool.

It's been tried and somewhat works in Linux, MacOS and Windows 10.

To build it you need:
 - zig version [0.11.0](https://ziglang.org/download) or newer
 - [libgit2](https://github.com/libgit2/libgit2).
 	- on Linux - use you package manager
    - on MacOS - `brew install libgit2`
    - on Windows - I build libgit2 from source and put header files in `./deps/include/` and lib file in `./deps/lib/`

Key bindings are hard-coded in the [source](src/key_bind.zig):
 - `k` - up
 - `j` - down
 - `a` - add new worktree from local branch
 - `d` - delete worktree
 - `q` or `ESC` - quit/back
 - `Enter` or `Space` - select item
 - `r` - toggle remote/local branch list

 ### Changing `CWD`

 The location of the chosen worktree's folder is written in a file named `zig-worktree.path` within the `TEMP` directory.

 I have the following in my bash startup script:
 ```bash
function gw() {
	path-to/zig-worktree
	if [ $? -eq 0 ]; then
		cd $(</tmp/zig-worktree.path)
	fi
}
 ```

 and for `powershell`
 ```powershell
 Function gw {
	path-to\zig-worktree.exe
	if ($LastExitCode -eq 0) {
	   cd $(Get-Content -Path  $env:TEMP\zig-worktree.path -Raw)
	}
}
 ```
