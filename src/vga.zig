const VGA_BUF: *volatile [80*25]u16 = @ptrFromInt(0xb8000);

pub const Color = enum(u8) {
    Black = 0, Blue, Green, Cyan, Red, Magenta, Brown, LightGrey,
    DarkGrey, LightBlue, LightGreen, LightCyan, LightRed, LightMagenta, Yellow, White,
};

fn entry(ch: u8, fgc: Color, bgc: Color) u16 {
    return (@as(u16, @intFromEnum(bgc)) << 12) | (@as(u16, @intFromEnum(fgc)) << 8) | ch;
}

var row: usize = 0;
var col: usize = 0;
var fg: Color = .LightGrey;
var bg: Color = .Black;

pub fn clear() void {
    row = 0; col = 0;
    const blank = entry(' ' , fg, bg);
    var i: usize = 0;
    while (i < 80*25) : (i += 1) VGA_BUF.*[i] = blank;
}

fn put_at(c: u8, r: usize, ccol: usize) void { VGA_BUF.*[r*80 + ccol] = entry(c, fg, bg); }

fn newline() void {
    col = 0;
    if (row + 1 < 25) {
        row += 1;
    } else {
        // Scroll up one line
        var r: usize = 1;
        while (r < 25) : (r += 1) {
            var c: usize = 0;
            while (c < 80) : (c += 1) {
                VGA_BUF.*[(r-1)*80 + c] = VGA_BUF.*[r*80 + c];
            }
        }
        const blank = entry(' ', fg, bg);
        var c2: usize = 0;
        while (c2 < 80) : (c2 += 1) VGA_BUF.*[(24)*80 + c2] = blank;
    }
}

pub fn write_byte(c: u8) void {
    switch (c) {
        '\n' => newline(),
        '\r' => { col = 0; },
        else => {
            if (col >= 80) newline();
            put_at(c, row, col);
            col += 1;
        },
    }
}

pub fn write(buf: []const u8) void {
    var i: usize = 0;
    while (i < buf.len) : (i += 1) write_byte(buf[i]);
}

pub fn set_color(new_fg: Color, new_bg: Color) void { fg = new_fg; bg = new_bg; }
pub fn init() void { clear(); }
