const std = @import("std");
const Allocator = std.mem.Allocator;
const bun = @import("root").bun;
const logger = bun.logger;
const Log = logger.Log;

pub const css = @import("../css_parser.zig");
pub const css_values = @import("../values/values.zig");
pub const Printer = css.Printer;
pub const PrintErr = css.PrintErr;
const DashedIdent = css_values.ident.DashedIdent;
const DashedIdentFns = css_values.ident.DashedIdentFns;
const Ident = css_values.ident.Ident;
pub const Error = css.Error;

pub const CssColor = css.css_values.color.CssColor;
pub const RGBA = css.css_values.color.RGBA;
pub const SRGB = css.css_values.color.SRGB;
pub const HSL = css.css_values.color.HSL;
pub const CSSInteger = css.css_values.number.CSSInteger;
pub const CSSIntegerFns = css.css_values.number.CSSIntegerFns;
pub const Url = css.css_values.url.Url;
pub const DashedIdentReference = css.css_values.ident.DashedIdentReference;
pub const CustomIdent = css.css_values.ident.CustomIdent;
pub const CustomIdentFns = css.css_values.ident.CustomIdentFns;
pub const LengthValue = css.css_values.length.LengthValue;
pub const Angle = css.css_values.angle.Angle;
pub const Time = css.css_values.time.Time;
pub const Resolution = css.css_values.resolution.Resolution;
pub const AnimationName = css.css_properties.animation.AnimationName;
const ComponentParser = css.css_values.color.ComponentParser;

const ArrayList = std.ArrayListUnmanaged;

/// PERF: nullable optimization
pub const TokenList = struct {
    v: std.ArrayListUnmanaged(TokenOrValue),

    const This = @This();

    pub fn toCss(
        this: *const This,
        comptime W: type,
        dest: *Printer(W),
        is_custom_property: bool,
    ) PrintErr!void {
        if (!dest.minify and this.v.items.len == 1 and this.v.items[0].isWhitespace()) {
            return;
        }

        var has_whitespace = false;
        for (this.v.items, 0..) |*token_or_value, i| {
            switch (token_or_value.*) {
                .color => |color| {
                    try color.toCss(W, dest);
                    has_whitespace = false;
                },
                .unresolved_color => |color| {
                    try color.toCss(W, dest, is_custom_property);
                    has_whitespace = false;
                },
                .url => |url| {
                    if (dest.dependencies != null and is_custom_property and !url.isAbsolute()) {
                        @compileError(css.todo_stuff.errors);
                    }
                    try url.toCss(W, dest);
                    has_whitespace = false;
                },
                .@"var" => |@"var"| {
                    try @"var".toCss(W, dest, is_custom_property);
                    has_whitespace = try this.writeWhitespaceIfNeeded(i, dest);
                },
                .env => |env| {
                    try env.toCss(W, dest, is_custom_property);
                    has_whitespace = try this.writeWhitespaceIfNeeded(i, W, dest);
                },
                .function => |f| {
                    try f.toCss(W, dest, is_custom_property);
                    has_whitespace = try this.writeWhitespaceIfNeeded(i, W, dest);
                },
                .length => |v| {
                    // Do not serialize unitless zero lengths in custom properties as it may break calc().
                    const value, const unit = v.toUnitValue();
                    try try css.serializer.serializeDimension(value, unit, W, dest);
                    has_whitespace = false;
                },
                .angle => |v| {
                    try v.toCss(W, dest);
                    has_whitespace = false;
                },
                .resolution => |v| {
                    try v.toCss(W, dest);
                    has_whitespace = false;
                },
                .dashed_ident => |v| {
                    try DashedIdentFns.toCss(v, W, dest);
                    has_whitespace = false;
                },
                .animation_name => |v| {
                    try v.toCss(W, dest);
                    has_whitespace = false;
                },
                .token => |token| switch (token) {
                    .delim => |d| {
                        if (d == '+' or d == '-') {
                            try dest.writeChar(' ');
                            try dest.writeChar(d);
                            try dest.writeChar(' ');
                        } else {
                            const ws_before = !has_whitespace and (d == '/' or d == '*');
                            try dest.delim(d, ws_before);
                        }
                        has_whitespace = true;
                    },
                    .comma => {
                        try dest.delim(',', false);
                        has_whitespace = true;
                    },
                    .close_paren, .close_square, .close_curly => {
                        try token.toCss(W, dest);
                        has_whitespace = try this.writeWhitespaceIfNeeded(i, W, dest);
                    },
                    .dimension => {
                        try css.serializer.serializeDimension(token.dimension.value, token.dimension.unit, W, dest);
                        has_whitespace = false;
                    },
                    .number => {
                        try css.css_values.number.CSSNumberFns.toCss(W, dest);
                        has_whitespace = false;
                    },
                    else => {
                        try token.toCss(W, dest);
                        has_whitespace = token == .whitespace;
                    },
                },
            }
        }
    }

    pub fn writeWhitespaceIfNeeded(
        this: *const This,
        i: usize,
        comptime W: type,
        dest: *Printer(W),
    ) PrintErr!bool {
        _ = this; // autofix
        _ = i; // autofix
        _ = dest; // autofix
        @compileError(css.todo_stuff.depth);
    }

    pub fn parse(input: *css.Parser, options: *css.ParserOptions, depth: usize) Error!TokenList {
        var tokens = ArrayList(TokenOrValue){};
        try TokenListFns.parseInto(input, &tokens, options, depth);

        // Slice off leading and trailing whitespace if there are at least two tokens.
        // If there is only one token, we must preserve it. e.g. `--foo: ;` is valid.
        // TODO(zack): this feels like a common codepath, idk how I feel about reallocating a new array just to slice off whitespace.
        if (tokens.items.len >= 2) {
            var slice = tokens.items[0..];
            if (tokens.items.len > 0 and tokens.items[0].isWhitespace()) {
                slice = slice[1..];
            }
            if (tokens.items.len > 0 and tokens.items[tokens.items.len - 1].isWhitespace()) {
                slice = slice[0 .. slice.len - 1];
            }
            var newlist = ArrayList(TokenOrValue){};
            newlist.insertSlice(@compileError(css.todo_stuff.think_about_allocator), 0, slice) catch unreachable;
            tokens.deinit(@compileError(css.todo_stuff.think_about_allocator));
            return newlist;
        }

        return .{ .v = tokens };
    }

    pub fn parseRaw(
        input: *css.Parser,
        tokens: *ArrayList(TokenOrValue),
        options: *const css.ParserOptions,
        depth: usize,
    ) Error!void {
        if (depth > 500) {
            // return input.newCustomError(ParseError.maximum_nesting_depth);
            @compileError(css.todo_stuff.errors);
        }

        while (true) {
            const state = input.state();
            _ = state; // autofix
            const token = input.nextIncludingWhitespace() catch break;
            switch (token.*) {
                .open_paren, .open_square, .open_curly => {
                    tokens.append(
                        @compileError(css.todo_stuff.think_about_allocator),
                        .{ .token = token.* },
                    ) catch unreachable;
                    const closing_delimiter = switch (token.*) {
                        .open_paren => .close_paren,
                        .open_square => .close_square,
                        .open_curly => .close_curly,
                        else => unreachable,
                    };
                    const Closure = struct {
                        options: *const css.ParserOptions,
                        depth: usize,
                        tokens: *ArrayList(TokenOrValue),
                        pub fn parsefn(this: *@This(), input2: *css.Parser) Error!void {
                            return TokenListFns.parseRaw(
                                input2,
                                this.tokens,
                                this.options,
                                this.depth + 1,
                            );
                        }
                    };
                    var closure = Closure{
                        .options = options,
                        .depth = depth,
                        .tokens = tokens,
                    };
                    try input.parseNestedBlock(void, &closure, closure.parsefn);
                    tokens.append(
                        @compileError(css.todo_stuff.thinknk_about_allocator),
                        .{ .token = closing_delimiter },
                    ) catch unreachable;
                },
                .function => {
                    tokens.append(
                        @compileError(css.todo_stuff.think_about_allocator),
                        .{ .token = token.* },
                    ) catch unreachable;
                    const Closure = struct {
                        options: *const css.ParserOptions,
                        depth: usize,
                        tokens: *ArrayList(TokenOrValue),
                        pub fn parsefn(this: *@This(), input2: *css.Parser) Error!void {
                            return TokenListFns.parseRaw(
                                input2,
                                this.tokens,
                                this.options,
                                this.depth + 1,
                            );
                        }
                    };
                    var closure = Closure{
                        .options = options,
                        .depth = depth,
                        .tokens = tokens,
                    };
                    try input.parseNestedBlock(void, &closure, closure.parsefn);
                    tokens.append(
                        @compileError(css.todo_stuff.thinknk_about_allocator),
                        .{ .token = .close_paren },
                    ) catch unreachable;
                },
                else => {
                    tokens.append(
                        @compileError(css.todo_stuff.think_about_allocator),
                        .{ .token = token.* },
                    ) catch unreachable;
                },
            }
        }
    }

    pub fn parseInto(
        input: *css.Parser,
        tokens: *ArrayList(TokenOrValue),
        options: *const css.ParserOptions,
        depth: usize,
    ) Error!void {
        if (depth > 500) {
            // return input.newCustomError(ParseError.maximum_nesting_depth);
            @compileError(css.todo_stuff.errors);
        }

        var last_is_delim = false;
        var last_is_whitespace = false;

        while (true) {
            const state = input.state();
            const tok = input.nextIncludingWhitespace() catch break;
            switch (tok.*) {
                .whitespace, .comment => {
                    // Skip whitespace if the last token was a delimiter.
                    // Otherwise, replace all whitespace and comments with a single space character.
                    if (!last_is_delim) {
                        tokens.append(
                            @compileError(css.todo_stuff.think_about_allocator),
                            .{ .token = .{ .whitespace = " " } },
                        ) catch unreachable;
                        last_is_whitespace = true;
                    }
                },
                .function => |f| {
                    // Attempt to parse embedded color values into hex tokens.
                    if (tryParseColorToken(f, &state, input)) |color| {
                        tokens.append(
                            @compileError(css.todo_stuff.think_about_allocator),
                            .{ .color = color },
                        ) catch unreachable;
                        last_is_delim = false;
                        last_is_whitespace = true;
                    } else if (input.tryParse(UnresolvedColor.parse, .{ f, options })) |color| {
                        tokens.append(
                            @compileError(css.todo_stuff.think_about_allocator),
                            .{ .unresolved_color = color },
                        ) catch unreachable;
                        last_is_delim = false;
                        last_is_whitespace = true;
                    } else if (bun.strings.eql(f, "url")) {
                        input.reset(&state);
                        tokens.append(
                            @compileError(css.todo_stuff.think_about_allocator),
                            .{ .url = try Url.parse(input) },
                        ) catch unreachable;
                        last_is_delim = false;
                        last_is_whitespace = false;
                    } else if (bun.strings.eql(f, "var")) {
                        const Closure = struct {
                            options: *const css.ParserOptions,
                            depth: usize,
                            tokens: *ArrayList(TokenOrValue),
                            pub fn parsefn(this: *@This(), input2: *css.Parser) Error!TokenList {
                                const thevar = try TokenListFns.parse(input2, this.options, this.depth + 1);
                                return TokenOrValue{ .@"var" = thevar };
                            }
                        };
                        var closure = Closure{
                            .options = options,
                            .depth = depth,
                            .tokens = tokens,
                        };
                        const @"var" = try input.parseNestedBlock(TokenOrValue, &closure, Closure.parsefn);
                        tokens.append(
                            @compileError(css.todo_stuff.think_about_allocator),
                            @"var",
                        ) catch unreachable;
                        last_is_delim = true;
                        last_is_whitespace = false;
                    } else if (bun.strings.eql(f, "env")) {
                        const Closure = struct {
                            options: *const css.ParserOptions,
                            depth: usize,
                            pub fn parsefn(this: *@This(), input2: *css.Parser) Error!EnvironmentVariable {
                                const env = try EnvironmentVariable.parseNested(input2, this.options, depth + 1);
                                return TokenOrValue{ .env = env };
                            }
                        };
                        var closure = Closure{
                            .options = options,
                            .depth = depth,
                        };
                        const env = try input.parseNestedBlock(TokenOrValue, &closure, Closure.parsefn);
                        tokens.append(
                            @compileError(css.todo_stuff.think_about_allocator),
                            env,
                        ) catch unreachable;
                        last_is_delim = true;
                        last_is_whitespace = false;
                    } else {
                        const Closure = struct {
                            options: *const css.ParserOptions,
                            depth: usize,
                            pub fn parsefn(this: *@This(), input2: *css.Parser) Error!Function {
                                const args = try TokenListFns.parse(input2, this.options, this.depth + 1);
                                return args;
                            }
                        };
                        var closure = Closure{
                            .options = options,
                            .depth = depth,
                        };
                        const arguments = try input.parseNestedBlock(TokenList, &closure, Closure.parsefn);
                        tokens.append(
                            @compileError(css.todo_stuff.think_about_allocator),
                            .{
                                .function = .{
                                    .name = f,
                                    .arguments = arguments,
                                },
                            },
                        ) catch unreachable;
                        last_is_delim = true; // Whitespace is not required after any of these chars.
                        last_is_whitespace = false;
                    }
                },
                .hash, .idhash => {
                    const h = switch (tok.*) {
                        .hash => |h| h,
                        .idhash => |h| h,
                        else => unreachable,
                    };
                    brk: {
                        const r, const g, const b, const a = css.color.parseHashColor(h) orelse {
                            tokens.append(
                                @compileError(css.todo_stuff.think_about_allocator),
                                .{ .token = .{ .hash = h } },
                            ) catch unreachable;
                            break :brk;
                        };
                        tokens.append(
                            @compileError(css.todo_stuff.think_about_allocator),
                            .{
                                .color = CssColor{ .rgba = RGBA.new(r, g, b, a) },
                            },
                        ) catch unreachable;
                    }
                    last_is_delim = false;
                    last_is_whitespace = false;
                },
                .unquoted_url => {
                    input.reset(&state);
                    tokens.append(
                        @compileError(css.todo_stuff.think_about_allocator),
                        .{ .url = try Url.parse(input) },
                    ) catch unreachable;
                    last_is_delim = false;
                    last_is_whitespace = false;
                },
                .ident => |name| {
                    if (bun.strings.startsWith(name, "--")) {
                        tokens.append(@compileError(css.todo_stuff.think_about_allocator), .{ .dashed_ident = name }) catch unreachable;
                        last_is_delim = false;
                        last_is_whitespace = false;
                    }
                },
                .open_paren, .open_square, .open_curly => {
                    tokens.append(
                        @compileError(css.todo_stuff.think_about_allocator),
                        .{ .token = tok.* },
                    ) catch unreachable;
                    const closing_delimiter = switch (tok.*) {
                        .open_paren => .close_paren,
                        .open_square => .close_square,
                        .open_curly => .close_curly,
                        else => unreachable,
                    };
                    const Closure = struct {
                        options: *const css.ParserOptions,
                        depth: usize,
                        tokens: *ArrayList(TokenOrValue),
                        pub fn parsefn(this: *@This(), input2: *css.Parser) Error!void {
                            return TokenListFns.parseInto(
                                input2,
                                this.tokens,
                                this.options,
                                this.depth + 1,
                            );
                        }
                    };
                    var closure = Closure{
                        .options = options,
                        .depth = depth,
                        .tokens = tokens,
                    };
                    try input.parseNestedBlock(void, &closure, closure.parsefn);
                    tokens.append(
                        @compileError(css.todo_stuff.think_about_allocator),
                        .{ .token = closing_delimiter },
                    ) catch unreachable;
                    last_is_delim = true; // Whitespace is not required after any of these chars.
                    last_is_whitespace = false;
                },
                .dimension => {
                    const value = if (LengthValue.tryFromToken(tok)) |length|
                        TokenOrValue{ .length = length }
                    else if (Angle.tryFromToken(tok)) |angle|
                        TokenOrValue{ .angle = angle }
                    else if (Time.tryFromToken(tok)) |time|
                        TokenOrValue{ .time = time }
                    else if (Resolution.tryFromToken(tok)) |resolution|
                        TokenOrValue{ .resolution = resolution }
                    else
                        TokenOrValue{ .token = tok.* };

                    tokens.append(
                        @compileError(css.todo_stuff.think_about_allocator),
                        value,
                    ) catch unreachable;

                    last_is_delim = false;
                    last_is_whitespace = false;
                },
                else => {},
            }

            if (tok.isParseError()) {
                @compileError(css.todo_stuff.errors);
            }
            last_is_delim = switch (tok.*) {
                .delim, .comma => true,
                else => false,
            };

            // If this is a delimiter, and the last token was whitespace,
            // replace the whitespace with the delimiter since both are not required.
            if (last_is_delim and last_is_whitespace) {
                const last = &tokens.items[tokens.items.len - 1];
                last.* = .{ .token = tok.* };
            } else {
                tokens.append(
                    @compileError(css.todo_stuff.think_about_allocator),
                    .{ .token = tok.* },
                ) catch unreachable;
            }

            last_is_whitespace = false;
        }
    }
};
pub const TokenListFns = TokenList;

/// A color value with an unresolved alpha value (e.g. a variable).
/// These can be converted from the modern slash syntax to older comma syntax.
/// This can only be done when the only unresolved component is the alpha
/// since variables can resolve to multiple tokens.
pub const UnresolvedColor = union(enum) {
    /// An rgb() color.
    RGB: struct {
        /// The red component.
        r: f32,
        /// The green component.
        g: f32,
        /// The blue component.
        b: f32,
        /// The unresolved alpha component.
        alpha: TokenList,
    },
    /// An hsl() color.
    HSL: struct {
        /// The hue component.
        h: f32,
        /// The saturation component.
        s: f32,
        /// The lightness component.
        l: f32,
        /// The unresolved alpha component.
        alpha: TokenList,
    },
    /// The light-dark() function.
    light_dark: struct {
        /// The light value.
        light: TokenList,
        /// The dark value.
        dark: TokenList,
    },
    const This = @This();

    pub fn toCss(
        this: *const This,
        comptime W: type,
        dest: *Printer(W),
        is_custom_property: bool,
    ) PrintErr!void {
        _ = this; // autofix
        _ = dest; // autofix
        _ = is_custom_property; // autofix
        @compileError(css.todo_stuff.depth);
    }

    pub fn parse(
        input: *css.Parser,
        f: []const u8,
        options: *const css.ParserOptions,
    ) Error!UnresolvedColor {
        var parser = ComponentParser.new(false);
        // css.todo_stuff.match_ignore_ascii_case
        if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(f, "rgb")) {
            const Closure = struct {
                options: *const css.ParserOptions,
                parser: *ComponentParser,
                pub fn parsefn(this: *@This(), input2: *css.Parser) Error!UnresolvedColor {
                    return this.parser.parseRelative(input2, SRGB, UnresolvedColor, @This().innerParseFn, .{this.options});
                }
                pub fn innerParseFn(i: *css.Parser, p: *ComponentParser, opts: *const css.ParserOptions) Error!UnresolvedColor {
                    const r, const g, const b, const is_legacy = try css.css_values.color.parseRGBComponents(i, p);
                    if (is_legacy) {
                        @compileError(css.todo_stuff.errors);
                    }
                    try i.expectDelim('/');
                    const alpha = try TokenListFns.parse(i, opts, 0);
                    return UnresolvedColor{
                        .RGB = .{
                            .r = r,
                            .g = g,
                            .b = b,
                            .alpha = alpha,
                        },
                    };
                }
            };
            var closure = Closure{
                .options = options,
                .parser = &parser,
            };
            return try input.parseNestedBlock(UnresolvedColor, &closure, Closure.parsefn);
        } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(f, "hsl")) {
            const Closure = struct {
                options: *const css.ParserOptions,
                parser: *ComponentParser,
                pub fn parsefn(this: *@This(), input2: *css.Parser) Error!UnresolvedColor {
                    return this.parser.parseRelative(input2, HSL, UnresolvedColor, @This().innerParseFn, .{this.options});
                }
                pub fn innerParseFn(i: *css.Parser, p: *ComponentParser, opts: *const css.ParserOptions) Error!UnresolvedColor {
                    const h, const s, const l, const is_legacy = try css.css_values.color.parseHSLHWBComponents(HSL, i, p, false);
                    if (is_legacy) {
                        @compileError(css.todo_stuff.errors);
                    }
                    try i.expectDelim('/');
                    const alpha = try TokenListFns.parse(i, opts, 0);
                    return UnresolvedColor{
                        .HSL = .{
                            .h = h,
                            .s = s,
                            .l = l,
                            .alpha = alpha,
                        },
                    };
                }
            };
            var closure = Closure{
                .options = options,
                .parser = &parser,
            };
            return try input.parseNestedBlock(UnresolvedColor, &closure, Closure.parsefn);
        } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(f, "light-dark")) {
            const Closure = struct {
                options: *const css.ParserOptions,
                parser: *ComponentParser,
                pub fn parsefn(this: *@This(), input2: *css.Parser) Error!UnresolvedColor {
                    const light = try input2.parseUntilBefore(css.Delimiters{ .comma = true }, TokenList, this, @This().parsefn2);
                    errdefer light.deinit();
                    try input2.expectComma();
                    const dark = try TokenListFns.parse(input2, this.options, 0);
                    errdefer dark.deinit();
                    return UnresolvedColor{
                        .light_dark = .{
                            .light = light,
                            .dark = dark,
                        },
                    };
                }

                pub fn parsefn2(this: *@This(), input2: *css.Parser) Error!TokenList {
                    return TokenListFns.parse(input2, this.options, 1);
                }
            };
            var closure = Closure{
                .options = options,
                .parser = &parser,
            };
            return try input.parseNestedBlock(UnresolvedColor, &closure, Closure.parsefn);
        } else {
            // return input.newCustomError();
            @compileError(css.todo_stuff.errors);
        }
    }
};

/// A CSS variable reference.
pub const Variable = struct {
    /// The variable name.
    name: DashedIdentReference,
    /// A fallback value in case the variable is not defined.
    fallback: ?TokenList,

    const This = @This();

    pub fn toCss(
        this: *const This,
        comptime W: type,
        dest: *Printer(W),
    ) PrintErr!void {
        _ = this; // autofix
        _ = dest; // autofix
        @compileError(css.todo_stuff.depth);
    }
};

/// A CSS environment variable reference.
pub const EnvironmentVariable = struct {
    /// The environment variable name.
    name: EnvironmentVariableName,
    /// Optional indices into the dimensions of the environment variable.
    indices: ArrayList(CSSInteger) = ArrayList(CSSInteger).init(),
    /// A fallback value in case the variable is not defined.
    fallback: ?TokenList,

    pub fn parse(input: *css.Parser, options: *const css.ParserOptions, depth: usize) Error!EnvironmentVariable {
        try input.expectFunctionMatching("env");
        const Closure = struct {
            options: *const css.ParserOptions,
            depth: usize,
            pub fn parsefn(this: *@This(), i: *css.Parser) Error!EnvironmentVariableName {
                return EnvironmentVariable.parseNested(i, this.options, this.depth);
            }
        };
        var closure = Closure{
            .options = options,
            .depth = depth,
        };
        return input.parseNestedBlock(EnvironmentVariable, &closure, Closure.parsefn);
    }

    pub fn parseNested(input: *css.Parser, options: *const css.ParserOptions, depth: usize) Error!EnvironmentVariable {
        const name = try EnvironmentVariableName.parse();
        var indices = ArrayList(i32){};
        errdefer indices.deinit(@compileError(css.todo_stuff.think_about_allocator));
        while (input.tryParse(CSSIntegerFns.parse, .{}) catch null) |idx| {
            indices.append(
                @compileError(css.todo_stuff.think_about_allocator),
                idx,
            ) catch unreachable;
        }

        const fallback = if (input.tryParse(css.Parser.expectComma, .{})) |_| try TokenListFns.parse(input, options, depth + 1) else null;

        return EnvironmentVariable{
            .name = name,
            .indices = indices,
            .fallback = fallback,
        };
    }

    pub fn toCss(
        this: *const EnvironmentVariable,
        comptime W: type,
        dest: *Printer(W),
        is_custom_property: bool,
    ) PrintErr!void {
        _ = this; // autofix
        _ = dest; // autofix
        _ = is_custom_property; // autofix
        @compileError(css.todo_stuff.depth);
    }
};

/// A CSS environment variable name.
pub const EnvironmentVariableName = union(enum) {
    /// A UA-defined environment variable.
    ua: UAEnvironmentVariable,
    /// A custom author-defined environment variable.
    custom: DashedIdentReference,
    /// An unknown environment variable.
    unknown: CustomIdent,

    pub fn parse(input: *css.Parser) Error!EnvironmentVariableName {
        if (input.tryParse(UAEnvironmentVariable.parse, .{})) |ua| {
            return .{ .ua = ua };
        }

        if (input.tryParse(DashedIdentReference.parseWithOptions, .{
            css.ParserOptions.default(
                @compileError(css.todo_stuff.think_about_allocator),
            ),
        })) |dashed| {
            return .{ .custom = dashed };
        }

        const ident = try CustomIdentFns.parse(input);
        return .{ .unknown = ident };
    }
};

/// A UA-defined environment variable name.
pub const UAEnvironmentVariable = enum {
    /// The safe area inset from the top of the viewport.
    safe_area_inset_top,
    /// The safe area inset from the right of the viewport.
    safe_area_inset_right,
    /// The safe area inset from the bottom of the viewport.
    safe_area_inset_bottom,
    /// The safe area inset from the left of the viewport.
    safe_area_inset_left,
    /// The viewport segment width.
    viewport_segment_width,
    /// The viewport segment height.
    viewport_segment_height,
    /// The viewport segment top position.
    viewport_segment_top,
    /// The viewport segment left position.
    viewport_segment_left,
    /// The viewport segment bottom position.
    viewport_segment_bottom,
    /// The viewport segment right position.
    viewport_segment_right,

    pub fn parse(input: *css.Parser) Error!UAEnvironmentVariable {
        return css.comptime_parse(UAEnvironmentVariable, input);
    }
};

/// A custom CSS function.
pub const Function = struct {
    /// The function name.
    name: Ident,
    /// The function arguments.
    arguments: TokenList,

    const This = @This();

    pub fn toCss(
        this: *const This,
        comptime W: type,
        dest: *Printer(W),
    ) PrintErr!void {
        _ = this; // autofix
        _ = dest; // autofix
        @compileError(css.todo_stuff.depth);
    }
};

/// A raw CSS token, or a parsed value.
pub const TokenOrValue = union(enum) {
    /// A token.
    token: css.Token,
    /// A parsed CSS color.
    color: CssColor,
    /// A color with unresolved components.
    unresolved_color: UnresolvedColor,
    /// A parsed CSS url.
    url: Url,
    /// A CSS variable reference.
    @"var": Variable,
    /// A CSS environment variable reference.
    env: EnvironmentVariable,
    /// A custom CSS function.
    function: Function,
    /// A length.
    length: LengthValue,
    /// An angle.
    angle: Angle,
    /// A time.
    time: Time,
    /// A resolution.
    resolution: Resolution,
    /// A dashed ident.
    dashed_ident: DashedIdent,
    /// An animation name.
    animation_name: AnimationName,

    pub fn isWhitespace(self: *const TokenOrValue) bool {
        switch (self.*) {
            .token => |tok| return tok == .whitespace,
            else => return false,
        }
    }
};

/// A CSS custom property, representing any unknown property.
pub const CustomProperty = struct {
    /// The name of the property.
    name: CustomPropertyName,
    /// The property value, stored as a raw token list.
    value: TokenList,

    pub fn parse(name: CustomPropertyName, input: *css.Parser, options: *const css.ParserOptions) Error!CustomProperty {
        const Closure = struct {
            options: *const css.ParserOptions,

            pub fn parsefn(this: *@This(), input2: *css.Parser) Error!TokenList {
                return TokenListFns.parse(input2, this.options, 0);
            }
        };

        var closure = Closure{
            .options = options,
        };

        const value = try input.parseUntilBefore(
            css.Delimiters{
                .bang = true,
                .semicolon = true,
            },
            TokenList,
            &closure,
            Closure.parsefn,
        );

        return CustomProperty{
            .name = name,
            .value = value,
        };
    }
};

/// A CSS custom property name.
pub const CustomPropertyName = union(enum) {
    /// An author-defined CSS custom property.
    custom: DashedIdent,
    /// An unknown CSS property.
    unknown: Ident,

    pub fn fromStr(name: []const u8) CustomPropertyName {
        if (bun.strings.startsWith(name, "--")) return .{ .custom = name };
        return .{ .unknown = name };
    }
};

pub fn tryParseColorToken(f: []const u8, state: *const css.ParserState, input: *css.Parser) ?CssColor {
    // css.todo_stuff.match_ignore_ascii_case
    if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(f, "rgb") or
        bun.strings.eqlCaseInsensitiveASCIIICheckLength(f, "rgba") or
        bun.strings.eqlCaseInsensitiveASCIIICheckLength(f, "hsl") or
        bun.strings.eqlCaseInsensitiveASCIIICheckLength(f, "hsla") or
        bun.strings.eqlCaseInsensitiveASCIIICheckLength(f, "hwb") or
        bun.strings.eqlCaseInsensitiveASCIIICheckLength(f, "lab") or
        bun.strings.eqlCaseInsensitiveASCIIICheckLength(f, "lch") or
        bun.strings.eqlCaseInsensitiveASCIIICheckLength(f, "oklab") or
        bun.strings.eqlCaseInsensitiveASCIIICheckLength(f, "oklch") or
        bun.strings.eqlCaseInsensitiveASCIIICheckLength(f, "color") or
        bun.strings.eqlCaseInsensitiveASCIIICheckLength(f, "color-mix") or
        bun.strings.eqlCaseInsensitiveASCIIICheckLength(f, "light-dark"))
    {
        const s = input.state();
        input.reset(&state);
        if (CssColor.parse(input)) |color| {
            return color;
        }
        input.reset(&s);
    }

    return null;
}