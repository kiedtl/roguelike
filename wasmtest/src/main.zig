// we'll import this from JS-land
extern fn console_log_ex(message: [*]const u8, length: u8) void;

export fn add(a: i32, b: i32) i32 {
    const log = "happy happy joy joy";
    console_log_ex(log, log.len);
    return a + b;
}

pub fn main() void {}
