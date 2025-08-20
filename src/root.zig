const std = @import("std");
const assert = std.debug.assert;
const builtin = @import("builtin");

pub const options = struct {
    /// Buffer to be part of the struct itself.
    /// Defaults to the size of the pointer itself.
    short_string_size: usize = @sizeOf(?[]u8),
};

/// A variable length collection of characters.
/// The String is implemented as a german string-esque with a [N]u8
/// that is baked into the String struct itself e.g: <allocator, size, <tag<[N]u8|[]u8>>>
/// Its not quite a german string as it has the tag for the state which takes space, and the allocator vtable
/// for managing the memory, but its close enough.
/// The point is not to optimize the size of the struct, but instead to remove unnecessary allocations.
///
/// opt: options for this instance of the type
pub fn String(opt: options) type {
    // We can always fit at least as many string bytes where the pointer goes as the size of the pointer.
    const buf_size = @max(opt.short_string_size, @sizeOf(?[]u8));
    return struct {
        const Self = @This();

        const internalState = enum {
            alloced,
            buffer,
            reference,
        };

        const StringBuffer = union(internalState) {
            alloced: []u8,
            buffer: [buf_size]u8,
            reference: []const u8,
        };

        /// The allocator used for managing the buffer
        allocator: std.mem.Allocator,
        /// The total size of the String
        size: usize,
        // The slice holding the string bytes
        buffer: StringBuffer,

        /// Errors that may occur when using String
        pub const Error = error{
            OutOfMemory,
            InvalidRange,
            IsReference, // String is borred, function not allowed!
        };

        /// Creates a String with an Allocator
        /// ### example
        /// ```zig
        /// var str = String.init(allocator);
        /// // don't forget to deallocate
        /// defer str.deinit();
        /// ```
        /// User is responsible for managing the new String
        pub fn init(allocator: std.mem.Allocator) Self {
            // for windows non-ascii characters
            // check if the system is windows
            if (builtin.os.tag == std.Target.Os.Tag.windows) {
                _ = std.os.windows.kernel32.SetConsoleOutputCP(65001);
            }
            return .{
                .allocator = allocator,
                .buffer = StringBuffer{ .buffer = [_]u8{0} ** buf_size },
                .size = 0,
            };
        }

        pub fn initWithContents(allocator: std.mem.Allocator, contents: []const u8) Error!Self {
            var self = init(allocator);

            try self.concat(contents);

            return self;
        }
        pub fn initReference(buf: []const u8) Self {
            // for windows non-ascii characters
            // check if the system is windows
            if (builtin.os.tag == std.Target.Os.Tag.windows) {
                _ = std.os.windows.kernel32.SetConsoleOutputCP(65001);
            }
            return .{
                .allocator = undefined,
                .buffer = StringBuffer{ .reference = buf },
                .size = buf.len,
            };
        }

        /// Deallocates the internal buffer
        /// ### usage:
        /// ```zig
        /// var str = String.init(allocator);
        /// // deinit after the closure
        /// defer str.deinit();
        /// ```
        pub fn deinit(self: *Self) void {
            switch (self.buffer) {
                .alloced => |*a| {
                    self.allocator.free(a.*);
                },
                .reference, .buffer => return,
            }
        }

        // Return true if current string is allocated using allocator
        pub fn allocated(self: *const Self) bool {
            return self.buffer == .alloced;
        }

        /// Returns the size of the internal buffer
        pub fn capacity(self: Self) usize {
            const ret = switch (self.buffer) {
                .alloced => |a| a.len,
                .buffer => |b| b.len,
                .reference => 0, // There is no capacity to write to the string!
            };
            return ret;
        }

        /// Allocates space for the internal buffer
        /// Always moves contents of preallocated buffer to newly allocated memory
        /// Truncates string if bytes < self.size
        /// Use truncate() to move the contentes back into the buffer when it fits.
        pub fn allocate(self: *Self, bytes: usize) Error!void {
            switch (self.buffer) {
                .buffer => |*b| {
                    const tmp = self.allocator.alloc(u8, bytes) catch {
                        return Error.OutOfMemory;
                    };
                    self.size = @min(bytes, self.size);
                    @memcpy(tmp[0..self.size], b[0..self.size]);
                    self.buffer = .{ .alloced = tmp };
                },
                .alloced => |*a| {
                    a.* = self.allocator.realloc(a.*, bytes) catch {
                        return Error.OutOfMemory;
                    };
                },
                .reference => return Error.IsReference,
            }
        }

        /// Reallocates the the internal buffer to size.
        /// Moves the string into the preallocated buffer if it fits.
        /// Copies a referenced buffer to appropriet buffer.
        pub fn truncate(self: *Self) Error!void {
            switch (self.buffer) {
                .alloced => |a| {
                    if (self.size <= buf_size) {
                        // Change tag to buffer, but dont change the contents
                        self.buffer = .{ .buffer = self.buffer.alloced[0..buf_size].* };
                        @memcpy(self.buffer.buffer[0..self.size], a[0..self.size]);
                        self.allocator.free(a);
                        self.size = @min(self.size, buf_size);
                        return;
                    }
                    try self.allocate(self.size);
                },
                .buffer => |*b| {
                    self.size = b.len;
                },
                .reference => return Error.IsReference,
            }
        }

        /// Appends a character onto the end of the String
        pub fn concat(self: *Self, char: []const u8) Error!void {
            try self.insert(char, self.size);
        }

        fn rawBufBytesConst(self: *const Self) []const u8 {
            switch (self.buffer) {
                .alloced => |*a| {
                    return a.*;
                },
                .buffer => |*b| {
                    return b;
                },
                .reference => |*r| {
                    return r.*;
                },
            }
        }

        fn rawBufBytes(self: *Self) []u8 {
            switch (self.buffer) {
                .alloced => |*a| {
                    return a.*;
                },
                .buffer => |*b| {
                    return b;
                },
                .reference => |_| {
                    @panic("Not allowed to access mutable bytes of referenced string");
                },
            }
        }

        /// Inserts a string literal into the String at an index
        pub fn insert(self: *Self, literal: []const u8, index: usize) Error!void {
            if (self.buffer == .reference) return Error.IsReference;

            if (self.size + literal.len > self.capacity()) {
                try self.allocate(self.size + literal.len * 2);
            }

            // If the index is >= len, then simply push to the end.
            // If not, then copy contents over and insert literal.
            const self_len = self.len();
            var buffer = self.rawBufBytes();
            if (index >= self_len) {
                std.mem.copyBackwards(u8, buffer[self.size..], literal);
            } else {
                if (getIndex(buffer, index, true)) |k| {
                    std.mem.copyBackwards(u8, buffer[k + literal.len ..], buffer[k..self.size]);
                    std.mem.copyBackwards(u8, buffer[k .. k + literal.len], literal);
                }
            }

            self.size += literal.len;
        }

        /// Removes the last character from the String
        pub fn pop(self: *Self) !?[]const u8 {
            if (self.buffer == .reference) return Error.IsReference;
            if (self.size == 0) return null;

            var buffer = self.rawBufBytes();
            var i: usize = 0;
            while (i < self.size) {
                const size = getUTF8Size(buffer[i]);
                if (i + size >= self.size) break;
                i += size;
            }

            const ret = buffer[i..self.size];
            self.size -= (self.size - i);
            return ret;
        }

        /// Executes equality check between this String with a string literal
        pub fn eql(self: *const Self, literal: []const u8) bool {
            const buffer = self.rawBufBytesConst();
            return std.mem.eql(u8, buffer[0..self.size], literal);
        }

        /// Executes equality check between this String and other String
        pub fn eqlString(self: *const Self, other: *const Self) bool {
            const buffer = self.rawBufBytesConst();
            const other_buffer = other.rawBufBytesConst();
            return std.mem.eql(u8, buffer[0..self.size], other_buffer[0..other.size]);
        }

        /// Lexically compares this String with a string literal
        pub fn cmp(self: *const Self, literal: []const u8) std.math.Order {
            const buffer = self.rawBufBytesConst();
            return std.mem.order(u8, buffer[0..self.size], literal);
        }

        /// Lexically compares this String with a string literal
        pub fn cmpString(self: *const Self, other: *const Self) std.math.Order {
            const buffer = self.rawBufBytesConst();
            const other_buffer = other.rawBufBytesConst();
            return std.mem.order(u8, buffer[0..self.size], other_buffer[0..other.size]);
        }

        /// Returns the String buffer as a string literal
        /// ### usage:
        ///```zig
        ///var mystr = try String.init_with_contents(allocator, "Test String!");
        ///defer _ = mystr.deinit();
        ///std.debug.print("{s}\n", .{mystr.str()});
        ///```
        pub fn str(self: *const Self) []const u8 {
            if (self.size == 0) return "";
            const buffer = self.rawBufBytesConst();
            return buffer[0..self.size];
        }

        /// Returns an owned slice of this string
        pub fn toOwned(self: *const Self) Error!?[]u8 {
            const string = self.str();
            if (self.allocator.alloc(u8, string.len)) |newStr| {
                std.mem.copyForwards(u8, newStr, string);
                return newStr;
            } else |_| {
                return Error.OutOfMemory;
            }

            return null;
        }

        /// Returns a character at the specified index
        pub fn charAt(self: *const Self, index: usize) ?[]const u8 {
            var buffer = self.rawBufBytesConst();
            if (getIndex(buffer, index, true)) |i| {
                const size = getUTF8Size(buffer[i]);
                return buffer[i..(i + size)];
            }
            return null;
        }

        /// Returns amount of characters in the String
        pub fn len(self: *const Self) usize {
            var length: usize = 0;
            var i: usize = 0;

            const buf = self.rawBufBytesConst();
            while (i < self.size) {
                i += getUTF8Size(buf[i]);
                length += 1;
            }

            return length;
        }

        /// Finds the first occurrence of the string literal
        pub fn find(self: *const Self, literal: []const u8) ?usize {
            const buffer = self.rawBufBytesConst();
            const index = std.mem.indexOf(u8, buffer[0..self.size], literal);
            if (index) |i| {
                return getIndex(buffer, i, false);
            }

            return null;
        }

        /// Finds the last occurrence of the string literal
        pub fn rfind(self: *const Self, literal: []const u8) ?usize {
            const buffer = self.rawBufBytesConst();
            const index = std.mem.lastIndexOf(u8, buffer[0..self.size], literal);
            if (index) |i| {
                return getIndex(buffer, i, false);
            }

            return null;
        }

        /// Removes a character at the specified index
        pub fn remove(self: *Self, index: usize) Error!void {
            try self.removeRange(index, index + 1);
        }

        /// Removes a range of character from the String
        /// Start (inclusive) - End (Exclusive)
        pub fn removeRange(self: *Self, start: usize, end: usize) Error!void {
            if (self.buffer == .reference) return Error.IsReference;
            const length = self.len();
            if (end < start or end > length) return Error.InvalidRange;

            const buffer = self.rawBufBytes();
            const rStart = getIndex(buffer, start, true).?;
            const rEnd = getIndex(buffer, end, true).?;
            const difference = rEnd - rStart;

            var i: usize = rEnd;
            while (i < self.size) : (i += 1) {
                buffer[i - difference] = buffer[i];
            }

            self.size -= difference;
        }

        /// Trims all whitelist characters at the start of the String.
        pub fn trimStart(self: *Self, whitelist: []const u8) Error!void {
            if (self.buffer == .reference) return Error.IsReference;
            const buffer = self.rawBufBytes();
            var i: usize = 0;
            while (i < self.size) : (i += 1) {
                const size = getUTF8Size(buffer[i]);
                if (size > 1 or !inWhitelist(buffer[i], whitelist)) break;
            }

            if (getIndex(buffer, i, false)) |k| {
                self.removeRange(0, k) catch {};
            }
        }

        /// Trims all whitelist characters at the end of the String.
        pub fn trimEnd(self: *Self, whitelist: []const u8) Error!void {
            if (self.buffer == .reference) return Error.IsReference;
            self.reverse() catch unreachable;
            self.trimStart(whitelist) catch unreachable;
            self.reverse() catch unreachable;
        }

        /// Trims all whitelist characters from both ends of the String
        pub fn trim(self: *Self, whitelist: []const u8) Error!void {
            if (self.buffer == .reference) return Error.IsReference;
            self.trimStart(whitelist) catch unreachable;
            self.trimEnd(whitelist) catch unreachable;
        }

        /// Copies this String into a new one
        /// User is responsible for managing the new String
        pub fn clone(self: *const Self) Error!Self {
            return initWithContents(self.allocator, self.str());
        }

        /// Reverses the characters in this String
        pub fn reverse(self: *Self) Error!void {
            if (self.buffer == .reference) return Error.IsReference;
            var buffer = self.rawBufBytes();
            var i: usize = 0;
            while (i < self.size) {
                const size = getUTF8Size(buffer[i]);
                if (size > 1) std.mem.reverse(u8, buffer[i..(i + size)]);
                i += size;
            }

            std.mem.reverse(u8, buffer[0..self.size]);
        }

        /// Repeats this String n times
        pub fn repeat(self: *Self, n: usize) Error!void {
            try self.allocate(self.size * (n + 1));
            var buffer = self.rawBufBytes();
            for (1..n + 1) |i| {
                std.mem.copyForwards(u8, buffer[self.size * i ..], buffer[0..self.size]);
            }

            self.size *= (n + 1);
        }

        /// Checks the String is empty
        pub inline fn isEmpty(self: *Self) bool {
            return self.size == 0;
        }

        /// Splits the String into a slice, based on a delimiter and an index
        pub fn split(self: *const Self, delimiters: []const u8, index: usize) ?[]const u8 {
            const buffer = self.rawBufBytesConst();
            var i: usize = 0;
            var block: usize = 0;
            var start: usize = 0;

            while (i < self.size) {
                const size = getUTF8Size(buffer[i]);
                if (size == delimiters.len) {
                    if (std.mem.eql(u8, delimiters, buffer[i..(i + size)])) {
                        if (block == index) return buffer[start..i];
                        start = i + size;
                        block += 1;
                    }
                }

                i += size;
            }

            if (i >= self.size - 1 and block == index) {
                return buffer[start..self.size];
            }

            return null;
        }

        /// Splits the String into slices, based on a delimiter.
        pub fn splitAll(self: *const Self, delimiters: []const u8) ![][]const u8 {
            var splitArr = std.ArrayList([]const u8).init(self.allocator);
            defer splitArr.deinit();

            var i: usize = 0;
            while (self.split(delimiters, i)) |slice| : (i += 1) {
                try splitArr.append(slice);
            }

            return try splitArr.toOwnedSlice();
        }

        /// Splits the String into a new string, based on delimiters and an index
        /// The user of this function is in charge of the memory of the new String.
        pub fn splitToString(self: *const Self, delimiters: []const u8, index: usize) Error!?Self {
            if (self.split(delimiters, index)) |block| {
                var string = init(self.allocator);
                try string.concat(block);
                return string;
            }

            return null;
        }

        /// Splits the String into a slice of new Strings, based on delimiters.
        /// The user of this function is in charge of the memory of the new Strings.
        pub fn splitAllToStrings(self: *const Self, delimiters: []const u8) ![]Self {
            var splitArr = std.ArrayList(Self).init(self.allocator);
            defer splitArr.deinit();

            var i: usize = 0;
            while (try self.splitToString(delimiters, i)) |splitStr| : (i += 1) {
                try splitArr.append(splitStr);
            }

            return try splitArr.toOwnedSlice();
        }

        /// Splits the String into a slice of Strings by new line (\r\n or \n).
        pub fn lines(self: *Self) Error![]Self {
            var lineArr = std.ArrayList(Self).init(self.allocator);
            defer lineArr.deinit();

            var selfClone = try self.clone();
            defer selfClone.deinit();

            _ = try selfClone.replace("\r\n", "\n");

            return try selfClone.splitAllToStrings("\n");
        }

        /// Clears the contents of the String but leaves the capacity
        pub fn clear(self: *Self) Error!void {
            if (self.buffer == .reference) return Error.IsReference;
            const buffer = self.rawBufBytes();
            @memset(buffer, 0);
            self.size = 0;
        }

        /// Converts all (ASCII) uppercase letters to lowercase
        pub fn toLowercase(self: *Self) Error!void {
            if (self.buffer == .reference) return Error.IsReference;
            var buffer = self.rawBufBytes();
            var i: usize = 0;
            while (i < self.size) {
                const size = getUTF8Size(buffer[i]);
                if (size == 1) buffer[i] = std.ascii.toLower(buffer[i]);
                i += size;
            }
        }

        /// Converts all (ASCII) uppercase letters to lowercase
        pub fn toUppercase(self: *Self) Error!void {
            if (self.buffer == .reference) return Error.IsReference;
            var buffer = self.rawBufBytes();
            var i: usize = 0;
            while (i < self.size) {
                const size = getUTF8Size(buffer[i]);
                if (size == 1) buffer[i] = std.ascii.toUpper(buffer[i]);
                i += size;
            }
        }

        // Convert the first (ASCII) character of each word to uppercase
        pub fn toCapitalized(self: *Self) Error!void {
            if (self.buffer == .reference) return Error.IsReference;
            if (self.size == 0) return;

            var buffer = self.rawBufBytes();
            var i: usize = 0;
            var is_new_word: bool = true;

            while (i < self.size) {
                const char = buffer[i];

                if (std.ascii.isWhitespace(char)) {
                    is_new_word = true;
                    i += 1;
                    continue;
                }

                if (is_new_word) {
                    buffer[i] = std.ascii.toUpper(char);
                    is_new_word = false;
                }

                i += 1;
            }
        }

        /// Creates a String from a given range
        /// User is responsible for managing the new String
        pub fn substr(self: *const Self, start: usize, end: usize) Error!Self {
            var result = init(self.allocator);

            const buffer = self.rawBufBytesConst();
            if (getIndex(buffer, start, true)) |rStart| {
                if (getIndex(buffer, end, true)) |rEnd| {
                    if (rEnd < rStart or rEnd > self.size)
                        return Error.InvalidRange;
                    try result.concat(buffer[rStart..rEnd]);
                }
            }

            return result;
        }

        // Writer functionality for the String.
        pub usingnamespace struct {
            pub const Writer = std.io.Writer(*Self, Error, appendWrite);

            pub fn writer(self: *Self) Writer {
                return .{ .context = self };
            }

            fn appendWrite(self: *Self, m: []const u8) !usize {
                try self.concat(m);
                return m.len;
            }
        };

        // Iterator support
        pub usingnamespace struct {
            pub const StringIterator = struct {
                string: *const Self,
                index: usize,

                pub fn next(it: *StringIterator) ?[]const u8 {
                    const buffer = (it.string.rawBufBytesConst());
                    if (it.index == it.string.size) return null;
                    const i = it.index;
                    it.index += getUTF8Size(buffer[i]);
                    return buffer[i..it.index];
                }
            };

            pub fn iterator(self: *const Self) StringIterator {
                return StringIterator{
                    .string = self,
                    .index = 0,
                };
            }
        };

        /// Returns whether or not a character is whitelisted
        fn inWhitelist(char: u8, whitelist: []const u8) bool {
            var i: usize = 0;
            while (i < whitelist.len) : (i += 1) {
                if (whitelist[i] == char) return true;
            }

            return false;
        }

        /// Checks if byte is part of UTF-8 character
        inline fn isUTF8Byte(byte: u8) bool {
            return ((byte & 0x80) > 0) and (((byte << 1) & 0x80) == 0);
        }

        /// Returns the real index of a unicode string literal
        fn getIndex(unicode: []const u8, index: usize, real: bool) ?usize {
            var i: usize = 0;
            var j: usize = 0;
            while (i < unicode.len) {
                if (real) {
                    if (j == index) return i;
                } else {
                    if (i == index) return j;
                }
                i += getUTF8Size(unicode[i]);
                j += 1;
            }

            return null;
        }

        /// Returns the UTF-8 character's size
        inline fn getUTF8Size(char: u8) u3 {
            return std.unicode.utf8ByteSequenceLength(char) catch {
                return 1;
            };
        }

        /// Sets the contents of the String
        pub fn setStr(self: *Self, contents: []const u8) Error!void {
            try self.clear();
            try self.concat(contents);
        }

        /// Checks the start of the string against a literal
        pub fn startsWith(self: *Self, literal: []const u8) bool {
            const buffer = self.rawBufBytesConst();
            const index = std.mem.indexOf(u8, buffer[0..self.size], literal);
            if (index) |i| {
                return i == 0;
            }
            return false;
        }

        /// Checks the end of the string against a literal
        pub fn endsWith(self: *Self, literal: []const u8) bool {
            const buffer = self.rawBufBytesConst();
            const index = std.mem.lastIndexOf(u8, buffer[0..self.size], literal);
            const i: usize = self.size - literal.len;
            if (index) |j| {
                return j == i;
            }
            return false;
        }

        /// Replaces all occurrences of a string literal with another
        pub fn replace(self: *Self, needle: []const u8, replacement: []const u8) Error!bool {
            if (self.buffer == .reference) return Error.IsReference;
            var buffer = self.rawBufBytes();
            const input_size = self.size;
            const size = std.mem.replacementSize(u8, buffer[0..input_size], needle, replacement);
            const cap = self.capacity();
            if (size > cap) {
                try self.allocate(size);
                buffer = self.rawBufBytes();
            }
            self.size = size;
            return std.mem.replace(u8, buffer[0..input_size], needle, replacement, buffer) > 0;
        }

        /// Checks if the needle String is within the source String
        pub fn includesString(self: *const Self, needle: *const Self) bool {
            if (self.size == 0 or needle.size == 0) return false;

            const buffer = self.rawBufBytesConst();
            const needle_buffer = needle.rawBufBytesConst();
            const found_index = std.mem.indexOf(u8, buffer[0..self.size], needle_buffer[0..needle.size]);
            if (found_index == null) return false;
            return true;
        }

        /// Checks if the needle literal is within the source String
        pub fn includesLiteral(self: *const Self, needle: []const u8) bool {
            if (self.size == 0 or needle.len == 0) return false;

            var buffer = self.rawBufBytesConst();
            const found_index = std.mem.indexOf(u8, buffer[0..self.size], needle);
            if (found_index == null) return false;
            return true;
        }

        /// Assign a buffer allocated with allocator to self.
        /// This moves the ownership of the buf and the buf must not be freed by user after this.
        /// Use setStr() to assign a copy.
        ///
        /// Allocator is the allocator used to manage the buf, overwrites current allocator of self.
        /// Old buffer is freed and must not be used after this.
        pub fn assignBuf(self: *Self, allocator: std.mem.Allocator, buf: []u8) void {
            switch (self.buffer) {
                .alloced => |*a| {
                    self.allocator.free(a.*);
                    a.* = buf;
                },
                .reference, .buffer => self.buffer = .{ .alloced = buf },
            }
            self.size = buf.len;
            self.allocator = allocator;
        }

        // Set the String to reference a Slice []const u8 in memory.
        // The reference is immutable.
        pub fn referenceBuf(self: *Self, buf: []const u8) void {
            switch (self.buffer) {
                .buffer => self.buffer = .{ .reference = buf },
                .reference => self.buffer = .{ .reference = buf },
                .alloced => |*a| {
                    self.allocator.free(a.*);
                    self.buffer = .{ .reference = buf };
                },
            }
            self.size = buf.len;
        }
    };
}
