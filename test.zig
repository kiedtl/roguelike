const foo = struct { bar: usize };

pub fn main() void {
    _ = @field(foo, .bar);
}
