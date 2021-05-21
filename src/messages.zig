pub const Message = struct {
    str: []const u8,
    type: MessageType = .Info,
};
