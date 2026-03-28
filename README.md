# Json Parser for Zig
A minimal implementation of a Json parser in Zig.

## Usage
Download the 'json.zig' module in the source folder and import it. Below is a usage example.
```
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
```

## Limitations
This parser was made for educational purposes. It implements the Json spec for the most part, but certain features (such as the unicode escape character \uXXXX) are not accounted for. For this reason it is not advised to use this parser in production environments, but instead to use the Zig standard library's built in Json parsing functionality.

## License
This library is provided as is. The author(s) take no responsibility for any possible damages caused by this library.
