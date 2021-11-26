pub const graph = @import("graph.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
