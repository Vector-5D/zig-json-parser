const std = @import("std");
const root = @import("root");
const json = root.json;

pub fn main() !void {
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});
}
