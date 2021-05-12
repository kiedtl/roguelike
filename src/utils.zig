pub fn saturating_sub(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
    return if ((a -% b) > a) 0 else a - b;
}
