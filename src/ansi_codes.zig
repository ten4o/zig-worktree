pub const ESC = "\x1b";
pub const CSI = ESC ++ "[";
pub const ALTERNATE_SCREEN_ENABLE = CSI ++ "?1049h";
pub const ALTERNATE_SCREEN_DISABLE = CSI ++ "?1049l";
pub const RESTORE_SCREEN = CSI ++ "?47l";
pub const SAVE_SCREEN = CSI ++ "?47h";
pub const CLEAR_SCREEN = CSI ++ "2J";
pub const CURSOR_HOME = CSI ++ "H";
pub const CURSOR_HIDE = CSI ++ "?25l";
pub const CURSOR_SHOW = CSI ++ "?25h";
pub const ENTER_SCREEN = SAVE_SCREEN ++ ALTERNATE_SCREEN_ENABLE ++ CLEAR_SCREEN ++ CURSOR_HIDE;
pub const EXIT_SCREEN = ALTERNATE_SCREEN_DISABLE ++ RESTORE_SCREEN ++ CURSOR_SHOW;

pub const BOXthin = "┌─┐│└┘├┤┬┴┼";
pub const BOXthick = "┏━┓┃┗┛┣┫┳┻╋";

pub fn Boxed(comptime def: []const u8) type {
    return struct {
        pub const tl = def[0..3];
        pub const hr = def[3..6];
        pub const tr = def[6..9];
        pub const vt = def[9..12];
        pub const bl = def[12..15];
        pub const br = def[15..18];
        pub const teeR = def[18..21];
        pub const teeL = def[21..24];
    };
}
