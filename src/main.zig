const std = @import("std");
const json = @import("json.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var root = try json.JsonRoot.init("data/data1.json", allocator);
    defer root.deinit();

    var write_buf: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&write_buf);
    const writer = &stdout_writer.interface;

    try json.printJsonValue(root.root, writer);
    try writer.print("\n", .{});
    try writer.flush();
}

test "object key lookup" {
    const allocator = std.testing.allocator;
    var root = try json.JsonRoot.init("data/data1.json", allocator);
    defer root.deinit();

    const val = json.searchJsonValue(root.root, "details.name");
    try std.testing.expect(val != null);
    try std.testing.expectEqualStrings("Alice", val.?.*.String);
}

test "array index" {
    const allocator = std.testing.allocator;
    var root = try json.JsonRoot.init("data/data1.json", allocator);
    defer root.deinit();

    const val = json.searchJsonValue(root.root, "numbers[2]");
    try std.testing.expect(val != null);
    try std.testing.expectEqual(@as(f64, 3), val.?.*.Number);
}

test "missing key returns null" {
    const allocator = std.testing.allocator;
    var root = try json.JsonRoot.init("data/data1.json", allocator);
    defer root.deinit();

    const val = json.searchJsonValue(root.root, "doesnotexist");
    try std.testing.expect(val == null);
}

test "bool value" {
    const allocator = std.testing.allocator;
    var root = try json.JsonRoot.init("data/data1.json", allocator);
    defer root.deinit();

    const val = json.searchJsonValue(root.root, "active");
    try std.testing.expect(val != null);
    try std.testing.expectEqual(true, val.?.*.Bool);
}
