const std = @import("std");

pub const JsonError = error{
    ValueParsingError,
    BoolParsingError,
    StringParsingError,
    JsonParsingError,
    ArrayParsingError,
    ObjectParsingError,
};

pub const JsonPair = struct {
    key: []const u8,
    value: *JsonValue,
};

pub const JsonValue = union(enum) {
    Null,
    Bool: bool,
    Number: f64,
    String: []u8,
    Array: []JsonValue,
    Object: []JsonPair,
};

pub const JsonRoot = struct {
    root: *JsonValue,
    buf: []u8,
    allocator: std.mem.Allocator,

    pub fn init(filepath: []const u8, allocator: std.mem.Allocator) !JsonRoot {
        const file = try std.fs.cwd().openFile(filepath, .{});
        defer file.close();

        const size = (try file.stat()).size;
        const buf: []u8 = try allocator.alloc(u8, size);

        var read_buf: [4096]u8 = undefined;
        var file_reader = file.reader(&read_buf);
        const reader: *std.Io.Reader = &file_reader.interface;

        try reader.readSliceAll(buf);

        var i: usize = 0;
        const root = try readValue(buf, &i, allocator);

        return .{ .root = root, .buf = buf, .allocator = allocator };
    }

    pub fn deinit(self: *JsonRoot) void {
        freeValue(self.root, self.allocator);
        self.allocator.free(self.buf);
        self.allocator.destroy(self.root);
    }
};

pub fn searchJsonValue(root: *JsonValue, path: []const u8) ?*JsonValue {
    var current = root;
    var i: usize = 0;

    while (i < path.len) {
        var end = i;

        while (end < path.len and path[end] != '.') end += 1;

        const segment = path[i..end];

        switch (current.*) {
            .Object => |obj| {
                var key_end = segment.len;
                for (segment, 0..) |c, j| {
                    if (c == '[') {
                        key_end = j;
                        break;
                    }
                }
                const key = segment[0..key_end];

                var found = false;
                for (obj) |pair| {
                    if (std.mem.eql(u8, pair.key, key)) {
                        current = pair.value;
                        found = true;
                        break;
                    }
                }
                if (!found) return null;

                if (key_end < segment.len) {
                    const arr_index_slice = segment[key_end + 1 .. segment.len - 1];
                    const arr_index = std.fmt.parseInt(usize, arr_index_slice, 10) catch return null;
                    switch (current.*) {
                        .Array => |arr| {
                            if (arr_index >= arr.len) return null;
                            current = &arr[arr_index];
                        },
                        else => return null,
                    }
                }
            },
            .Array => |arr| {
                var bracket = segment.len;
                for (segment, 0..) |c, j| {
                    if (c == '[') {
                        bracket = j;
                        break;
                    }
                }
                const arr_index_slice = segment[bracket + 1 .. segment.len - 1];
                const arr_index = std.fmt.parseInt(usize, arr_index_slice, 10) catch return 0;
                if (arr_index >= arr.len) return null;
                current = &arr[arr_index];
            },
            else => return null,
        }

        i = if (end < path.len) end + 1 else end;
    }

    return current;
}

pub fn printJsonValue(value: *JsonValue, writer: *std.Io.Writer) !void {
    switch (value.*) {
        .Null => try writer.writeAll("null"),
        .Bool => |b| try writer.print("{}", .{b}),
        .Number => |n| try writer.print("{d}", .{n}),
        .String => |s| try writer.print("\"{s}\"", .{s}),
        .Array => |arr| {
            try writer.writeAll("[");
            for (arr, 0..) |*val, idx| {
                try printJsonValue(val, writer);
                if (idx < arr.len - 1) try writer.writeAll(", ");
            }
            try writer.writeAll("]");
        },
        .Object => |obj| {
            try writer.writeAll("{");
            for (obj, 0..) |pair, idx| {
                try writer.print("\"{s}\": ", .{pair.key});
                try printJsonValue(pair.value, writer);
                if (idx < obj.len - 1) try writer.writeAll(", ");
            }
            try writer.writeAll("}");
        },
    }
}

fn freeValue(value: *JsonValue, allocator: std.mem.Allocator) void {
    switch (value.*) {
        .String => |s| {
            allocator.free(s);
        },
        .Array => |arr| {
            for (arr) |*val| {
                freeValue(val, allocator);
            }
            allocator.free(arr);
        },
        .Object => |obj| {
            for (obj) |pair| {
                allocator.free(pair.key);
                freeValue(pair.value, allocator);
                allocator.destroy(pair.value);
            }
            allocator.free(obj);
        },
        else => {},
    }
}

fn readValue(buf: []u8, i: *usize, allocator: std.mem.Allocator) (std.mem.Allocator.Error || JsonError || std.fmt.ParseFloatError)!*JsonValue {
    skipWhitespace(buf, i);

    const val: *JsonValue = try allocator.create(JsonValue);
    errdefer allocator.destroy(val);

    // String
    if (buf[i.*] == '"') {
        val.* = .{ .String = try readString(buf, i, allocator) };
        return val;
    }

    // Number
    if (std.ascii.isDigit(buf[i.*]) or buf[i.*] == '-') {
        val.* = .{ .Number = try readNumber(buf, i) };
        return val;
    }

    // Bool
    if (matchLiteral(buf, i.*, "true") or matchLiteral(buf, i.*, "false")) {
        val.* = .{ .Bool = try readBool(buf, i) };
        return val;
    }

    // Null
    if (matchLiteral(buf, i.*, "null")) {
        val.* = .Null;
        i.* += 4;
        return val;
    }

    // Array
    if (buf[i.*] == '[') {
        val.* = .{ .Array = try readArray(buf, i, allocator) };
        return val;
    }

    // Object
    if (buf[i.*] == '{') {
        val.* = .{ .Object = try readObject(buf, i, allocator) };
        return val;
    }

    return JsonError.ValueParsingError;
}

fn readNumber(buf: []u8, i: *usize) (std.mem.Allocator.Error || JsonError || std.fmt.ParseFloatError)!f64 {
    var num_str: [32]u8 = undefined;
    var n: usize = 0;

    while (i.* < buf.len and isNumberChar(buf[i.*])) : ({
        n += 1;
        i.* += 1;
    }) {
        num_str[n] = buf[i.*];
    }

    return try std.fmt.parseFloat(f64, num_str[0..n]);
}

fn readBool(buf: []u8, i: *usize) !bool {
    if (matchLiteral(buf, i.*, "true")) {
        i.* += 4;
        return true;
    } else if (matchLiteral(buf, i.*, "false")) {
        i.* += 5;
        return false;
    }
    return JsonError.BoolParsingError;
}

fn readString(buf: []u8, i: *usize, allocator: std.mem.Allocator) ![]u8 {
    if (buf[i.*] != '"') return JsonError.StringParsingError;
    i.* += 1; // skip first quote

    const start: usize = i.*;
    var scan_pos: usize = start;

    while (scan_pos < buf.len) {
        if (buf[scan_pos] == '"') {
            var backslash_count: usize = 0;
            var prev = scan_pos;
            while (prev > start) {
                prev -= 1;
                if (buf[prev] == '\\') backslash_count += 1 else break;
            }
            if (backslash_count % 2 == 0) break;
        }
        scan_pos += 1;
    }

    // string should end on another double quote
    if (scan_pos >= buf.len or buf[scan_pos] != '"') {
        return JsonError.StringParsingError;
    }

    const length: usize = scan_pos - start;
    const result = try allocator.alloc(u8, length);
    errdefer allocator.free(result);

    var in: usize = start;
    var out: usize = 0;

    while (in < scan_pos) {
        if (buf[in] == '\\') {
            in += 1;
            if (in >= scan_pos) return JsonError.StringParsingError;
            switch (buf[in]) {
                '"' => result[out] = '"',
                '\\' => result[out] = '\\',
                '/' => result[out] = '/',
                'b' => result[out] = 0x08,
                'f' => result[out] = 0x0C,
                'n' => result[out] = '\n',
                'r' => result[out] = '\r',
                't' => result[out] = '\t',
                'u' => return JsonError.StringParsingError, // TODO
                else => return JsonError.StringParsingError,
            }
        } else {
            if (buf[in] < 0x20) return JsonError.StringParsingError;
            result[out] = buf[in];
        }
        in += 1;
        out += 1;
    }

    i.* = scan_pos + 1; // skip closing quote
    return result[0..out];
}

fn readArray(buf: []u8, i: *usize, allocator: std.mem.Allocator) ![]JsonValue {
    i.* += 1; // skip '['
    skipWhitespace(buf, i);

    var list: std.ArrayList(JsonValue) = .empty;
    defer list.deinit(allocator);

    while (i.* < buf.len and buf[i.*] != ']') {
        const value = try readValue(buf, i, allocator);
        try list.append(allocator, value.*);
        allocator.destroy(value);
        skipWhitespace(buf, i);

        if (i.* < buf.len and buf[i.*] == ',') {
            i.* += 1;
            skipWhitespace(buf, i);
        }
    }

    if (i.* >= buf.len or buf[i.*] != ']') return JsonError.ArrayParsingError;
    i.* += 1; // skip ']'

    return try list.toOwnedSlice(allocator);
}

fn readObject(buf: []u8, i: *usize, allocator: std.mem.Allocator) ![]JsonPair {
    i.* += 1; // skip '{'
    skipWhitespace(buf, i);

    var list: std.ArrayList(JsonPair) = .empty;
    defer list.deinit(allocator);

    while (i.* < buf.len and buf[i.*] != '}') {
        const key = try readString(buf, i, allocator);
        skipWhitespace(buf, i);

        if (buf[i.*] != ':') return JsonError.ObjectParsingError;
        i.* += 1; // skip ':'
        skipWhitespace(buf, i);

        const value = try readValue(buf, i, allocator);
        try list.append(allocator, .{ .key = key, .value = value });
        skipWhitespace(buf, i);

        if (i.* < buf.len and buf[i.*] == ',') {
            i.* += 1; // skip ','
            skipWhitespace(buf, i);
        }
    }

    if (i.* >= buf.len or buf[i.*] != '}') return JsonError.ObjectParsingError;
    i.* += 1;

    return try list.toOwnedSlice(allocator);
}

fn skipWhitespace(buf: []u8, i: *usize) void {
    while (i.* < buf.len and (buf[i.*] == ' ' or buf[i.*] == '\n' or buf[i.*] == '\t')) {
        i.* += 1;
    }
}

fn matchLiteral(buf: []u8, i: usize, literal: []const u8) bool {
    return i + literal.len <= buf.len and std.mem.eql(u8, buf[i .. i + literal.len], literal);
}

fn isNumberChar(c: u8) bool {
    return std.ascii.isDigit(c) or c == '-' or c == '.' or c == 'e' or c == 'E' or c == '+';
}
