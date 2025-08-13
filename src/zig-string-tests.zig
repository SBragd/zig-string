const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const String = @import("root.zig").String(0);

test "Basic Usage" {
    // Create your String
    var myString = String.init(std.testing.allocator);
    defer myString.deinit();

    // Use functions provided
    try myString.concat("🔥 Hello!");
    _ = myString.pop();
    try myString.concat(", World 🔥");

    // Success!
    try expect(myString.eql("🔥 Hello, World 🔥"));
}

test "String Tests" {
    // This is how we create the String
    var myStr = String.init(std.testing.allocator);
    defer myStr.deinit();

    // allocate & capacity
    try myStr.allocate(32);
    try expectEqual(myStr.capacity(), 32);
    try expectEqual(myStr.size, 0);

    // truncate
    try myStr.truncate();
    try expectEqual(myStr.capacity(), @sizeOf(?[]u8));
    try expectEqual(myStr.size, 0);

    // concat
    try myStr.concat("A");
    try myStr.concat("\u{5360}");
    try myStr.concat("💯");
    try myStr.concat("Hello🔥");

    try expectEqual(myStr.size, 17);

    // pop & length
    try expectEqual(myStr.len(), 9);
    try expectEqualStrings(myStr.pop().?, "🔥");
    try expectEqual(myStr.len(), 8);
    try expectEqualStrings(myStr.pop().?, "o");
    try expectEqual(myStr.len(), 7);

    // str & eql
    try expect(myStr.eql("A\u{5360}💯Hell"));
    try expect(myStr.eql(myStr.str()));

    // charAt
    try expectEqualStrings(myStr.charAt(2).?, "💯");
    try expectEqualStrings(myStr.charAt(1).?, "\u{5360}");
    try expectEqualStrings(myStr.charAt(0).?, "A");

    // insert
    try myStr.insert("🔥", 1);
    try expectEqualStrings(myStr.charAt(1).?, "🔥");
    try expect(myStr.eql("A🔥\u{5360}💯Hell"));

    // find
    try expectEqual(myStr.find("🔥").?, 1);
    try expectEqual(myStr.find("💯").?, 3);
    try expectEqual(myStr.find("Hell").?, 4);

    // remove & removeRange
    try myStr.removeRange(0, 3);
    try expect(myStr.eql("💯Hell"));
    try myStr.remove(myStr.len() - 1);
    try expect(myStr.eql("💯Hel"));

    const whitelist = [_]u8{ ' ', '\t', '\n', '\r' };

    // trimStart
    try myStr.insert("      ", 0);
    myStr.trimStart(whitelist[0..]);
    try expect(myStr.eql("💯Hel"));

    // trimEnd
    _ = try myStr.concat("lo💯\n      ");
    myStr.trimEnd(whitelist[0..]);
    try expect(myStr.eql("💯Hello💯"));

    // clone
    var testStr = try myStr.clone();
    defer testStr.deinit();
    try expect(testStr.eql(myStr.str()));

    // reverse
    myStr.reverse();
    try expect(myStr.eql("💯olleH💯"));
    myStr.reverse();
    try expect(myStr.eql("💯Hello💯"));

    // repeat
    try myStr.repeat(2);
    try expect(myStr.eql("💯Hello💯💯Hello💯💯Hello💯"));

    // isEmpty
    try expect(!myStr.isEmpty());

    // split
    try expectEqualStrings(myStr.split("💯", 0).?, "");
    try expectEqualStrings(myStr.split("💯", 1).?, "Hello");
    try expectEqualStrings(myStr.split("💯", 2).?, "");
    try expectEqualStrings(myStr.split("💯", 3).?, "Hello");
    try expectEqualStrings(myStr.split("💯", 5).?, "Hello");
    try expectEqualStrings(myStr.split("💯", 6).?, "");

    var splitStr = String.init(std.testing.allocator);
    defer splitStr.deinit();

    try splitStr.concat("variable='value'");
    try expectEqualStrings(splitStr.split("=", 0).?, "variable");
    try expectEqualStrings(splitStr.split("=", 1).?, "'value'");

    // splitAll
    var splitAllStr = try String.init_with_contents(std.testing.allocator, "THIS IS A  TEST");
    defer splitAllStr.deinit();
    const splitAllSlices = try splitAllStr.splitAll(" ");

    try expectEqual(splitAllSlices.len, 5);
    try expectEqualStrings(splitAllSlices[0], "THIS");
    try expectEqualStrings(splitAllSlices[1], "IS");
    try expectEqualStrings(splitAllSlices[2], "A");
    try expectEqualStrings(splitAllSlices[3], "");
    try expectEqualStrings(splitAllSlices[4], "TEST");

    // splitToString
    var newSplit = try splitStr.splitToString("=", 0);
    try expect(newSplit != null);
    defer newSplit.?.deinit();

    try expectEqualStrings(newSplit.?.str(), "variable");

    // splitAllToStrings
    var splitAllStrings = try splitAllStr.splitAllToStrings(" ");
    defer for (splitAllStrings) |*str| {
        str.deinit();
    };

    try expectEqual(splitAllStrings.len, 5);
    try expectEqualStrings(splitAllStrings[0].str(), "THIS");
    try expectEqualStrings(splitAllStrings[1].str(), "IS");
    try expectEqualStrings(splitAllStrings[2].str(), "A");
    try expectEqualStrings(splitAllStrings[3].str(), "");
    try expectEqualStrings(splitAllStrings[4].str(), "TEST");

    // lines
    const lineSlice = "Line0\r\nLine1\nLine2";

    var lineStr = try String.init_with_contents(std.testing.allocator, lineSlice);
    defer lineStr.deinit();
    var linesSlice = try lineStr.lines();
    defer for (linesSlice) |*str| {
        str.deinit();
    };

    try expectEqual(linesSlice.len, 3);
    try expect(linesSlice[0].eql("Line0"));
    try expect(linesSlice[1].eql("Line1"));
    try expect(linesSlice[2].eql("Line2"));

    // toLowercase & toUppercase
    myStr.toUppercase();
    try expect(myStr.eql("💯HELLO💯💯HELLO💯💯HELLO💯"));
    myStr.toLowercase();
    try expect(myStr.eql("💯hello💯💯hello💯💯hello💯"));

    // substr
    var subStr = try myStr.substr(0, 7);
    defer subStr.deinit();
    try expect(subStr.eql("💯hello💯"));

    // clear
    myStr.clear();
    try expectEqual(myStr.len(), 0);
    try expectEqual(myStr.size, 0);

    // writer
    const writer = myStr.writer();
    const length = try writer.write("This is a Test!");
    try expectEqual(length, 15);

    // owned
    const mySlice = try myStr.toOwned();
    try expectEqualStrings(mySlice.?, "This is a Test!");
    std.testing.allocator.free(mySlice.?);

    // StringIterator
    var i: usize = 0;
    var iter = myStr.iterator();
    while (iter.next()) |ch| {
        if (i == 0) {
            try expectEqualStrings("T", ch);
        }
        i += 1;
    }

    try expectEqual(i, myStr.len());

    // setStr
    const contents = "setStr Test!";
    try myStr.setStr(contents);
    try expect(myStr.eql(contents));

    // non ascii supports in windows
    // try expectEqual(std.os.windows.kernel32.GetConsoleOutputCP(), 65001);
}

test "init with contents" {
    const initial_contents = "String with initial contents!";

    // This is how we create the String with contents at the start
    var myStr = try String.init_with_contents(std.testing.allocator, initial_contents);
    defer myStr.deinit();
    try expectEqualStrings(myStr.str(), initial_contents);
}

test "startsWith Tests" {
    var myString = String.init(std.testing.allocator);
    defer myString.deinit();

    try myString.concat("bananas");
    try expect(myString.startsWith("bana"));
    try expect(!myString.startsWith("abc"));
}

test "endsWith Tests" {
    var myString = String.init(std.testing.allocator);
    defer myString.deinit();

    try myString.concat("asbananas");
    try expect(myString.endsWith("nas"));
    try expect(!myString.endsWith("abc"));

    try myString.truncate();
    try myString.concat("💯hello💯💯hello💯💯hello💯");
    std.debug.print("", .{});
    try expect(myString.endsWith("hello💯"));
}

test "replace Tests" {
    // Create your String
    var myString = String.init(std.testing.allocator);
    defer myString.deinit();

    try myString.concat("hi,how are you");
    var result = try myString.replace("hi,", "");
    try expect(result);
    const s = myString.str();
    try expectEqualStrings(s, "how are you");

    result = try myString.replace("abc", " ");
    try expect(!result);

    myString.clear();
    try myString.concat("💯hello💯💯hello💯💯hello💯");
    _ = try myString.replace("hello", "hi");
    try expectEqualStrings(myString.str(), "💯hi💯💯hi💯💯hi💯");
}

test "rfind Tests" {
    var myString = try String.init_with_contents(std.testing.allocator, "💯hi💯💯hi💯💯hi💯");
    defer myString.deinit();

    try expectEqual(myString.rfind("hi"), 9);
}

test "toCapitalized Tests" {
    var myString = try String.init_with_contents(std.testing.allocator, "love and be loved");
    defer myString.deinit();

    myString.toCapitalized();

    try expectEqualStrings(myString.str(), "Love And Be Loved");
}

test "includes Tests" {
    var myString = try String.init_with_contents(std.testing.allocator, "love and be loved");
    defer myString.deinit();

    var needle = try String.init_with_contents(std.testing.allocator, "be");
    defer needle.deinit();

    try expect(myString.includesLiteral("and"));
    try expect(myString.includesString(&needle));

    try needle.concat("t");

    try expect(myString.includesLiteral("tiger") == false);
    try expect(myString.includesString(&needle) == false);

    needle.clear();

    try expect(myString.includesLiteral("") == false);
    try expect(myString.includesString(&needle) == false);
}

test "cmp and eql Test" {
    var myString = try String.init_with_contents(std.testing.allocator, "aba");
    defer myString.deinit();
    var otherString = try String.init_with_contents(std.testing.allocator, "bab");
    defer myString.deinit();

    try expect(myString.eql(myString.str()));
    try expect(!myString.eqlString(&otherString));
    try expect(myString.cmp(otherString.str()) == .lt);
    try expect(myString.cmpString(&otherString) == .lt);
    try expect(myString.cmp(myString.str()) == .eq);
    try expect(myString.cmpString(&myString) == .eq);
}
