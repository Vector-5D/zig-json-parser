const std = @import("std");

const JsonError = error{
    ValueParsingError,
    BoolParsingError,
};

const JsonPair = struct {
    key: []const u8,
    value: *JsonValue,
};

const JsonValue = union(enum) {
    Null,
    Bool: bool,
    Number: f64,
    String: []u8,
    Array: []JsonValue,
    Object: []JsonPair,
};

const JsonRoot = struct {
    root: *JsonValue,
    buf: []u8,
    allocator: std.mem.Allocator,

    pub fn init(filepath: []u8, allocator: std.mem.Allocator) !JsonRoot {
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
        freeValue(self.root);
        self.allocator.free(self.buf);
    }
};

fn freeValue(self: *const JsonRoot, value: *JsonValue) void {
    switch (value.*) {
        .String => |s| {
            self.allocator.free(s);
        },
        .Array => |arr| {
            for (arr) |*val| {
                freeValue(self, val);
            }
            self.allocator.free(arr);
        },
        .Object => |obj| {
            for (obj) |pair| {
                self.allocator.free(pair.key);
                freeValue(self, pair.value);
            }
            self.allocator.free(obj);
        },
        else => {},
    }
    self.allocator.free(value);
}

fn readValue(buf: []u8, i: *usize, allocator: std.mem.Allocator) !*JsonValue {
    skipWhitespace(buf, i);

    // String
    if (buf[i.*] == '"') {
        const val: *JsonValue = try allocator.create(JsonValue);
        val.* = .{ .String = try readString(buf, i, allocator) };
        return val;
    }

    // Number
    if (std.ascii.isDigit(buf[i.*]) or buf[i.*] == '-') {
        const val: *JsonValue = try allocator.create(JsonValue);
        val.* = .{ .Number = try readNumber(buf, i) };
        return val;
    }

    // Bool
    if (matchLiteral(buf, i.*, "true") or matchLiteral(buf, i.*, "false")) {
        const val: *JsonValue = try allocator.create(JsonValue);
        val.* = .{ .Bool = try readBool(buf, i) };
        return val;
    }

    // Null
    if (matchLiteral(buf, i.*, "null")) {
        const val: *JsonValue = try allocator.create(JsonValue);
        val.* = .Null;
        i.* += 4;
        return val;
    }

    // Array
    if (buf[i.*] == '[') {
        const val: *JsonValue = try readArray(buf, i, allocator);
        return val;
    }

    // Object
    if (buf[i.*] == '{') {
        const val: *JsonValue = try readObject(buf, i, allocator);
        return val;
    }

    return JsonError.ValueParsingError;
}

fn readNumber(buf: []u8, i: *usize) !f64 {
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

fn readString(buf: []u8, i: *usize, allocator: std.mem.Allocator) ![]u8 {}
fn readArray(buf: []u8, i: *usize, allocator: std.mem.Allocator) ![]JsonValue {}
fn readObject(buf: []u8, i: *usize, allocator: std.mem.Allocator) ![]JsonPair {}

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
