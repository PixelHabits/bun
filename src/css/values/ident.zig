const std = @import("std");
const Allocator = std.mem.Allocator;
const bun = @import("root").bun;
const logger = bun.logger;
const Log = logger.Log;

pub const css = @import("../css_parser.zig");
pub const Error = css.Error;
pub const Printer = css.Printer;
pub const PrintErr = css.PrintErr;

const Specifier = css.css_properties.css_modules.Specifier;

/// A CSS [`<dashed-ident>`](https://www.w3.org/TR/css-values-4/#dashed-idents) reference.
///
/// Dashed idents are used in cases where an identifier can be either author defined _or_ CSS-defined.
/// Author defined idents must start with two dash characters ("--") or parsing will fail.
///
/// In CSS modules, when the `dashed_idents` option is enabled, the identifier may be followed by the
/// `from` keyword and an argument indicating where the referenced identifier is declared (e.g. a filename).
pub const DashedIdentReference = struct {
    /// The referenced identifier.
    ident: DashedIdent,
    /// CSS modules extension: the filename where the variable is defined.
    /// Only enabled when the CSS modules `dashed_idents` option is turned on.
    from: ?Specifier,

    pub fn parseWithOptions(input: *css.Parser, options: *const css.ParserOptions) Error!DashedIdentReference {
        const ident = try DashedIdentFns.parse(input);

        const from = if (options.css_modules.config != null and options.css_modules.config.dashed_idents)
            if (input.tryParse(css.Parser.expectIdentMatching, .{"from"})) try Specifier.parse(input) else null
        else
            null;

        return DashedIdentReference{ .ident = ident, .from = from };
    }
};

/// A CSS [`<dashed-ident>`](https://www.w3.org/TR/css-values-4/#dashed-idents) declaration.
///
/// Dashed idents are used in cases where an identifier can be either author defined _or_ CSS-defined.
/// Author defined idents must start with two dash characters ("--") or parsing will fail.
pub const DashedIdent = []const u8;
pub const DashedIdentFns = struct {
    pub fn parse(input: *css.Parser) Error!DashedIdent {
        const location = input.currentSourceLocation();
        const ident = try input.expectIdent();
        if (bun.strings.startsWith(ident, "--")) return location.newUnexpectedTokenError(.{ .ident = ident });

        return ident;
    }

    const This = @This();

    pub fn toCss(this: *const DashedIdent, comptime W: type, dest: *Printer(W)) PrintErr!void {
        return dest.writeDashedIdent(this, true);
    }
};

/// A CSS [`<ident>`](https://www.w3.org/TR/css-values-4/#css-css-identifier).
pub const Ident = []const u8;

pub const IdentFns = struct {
    pub fn parse(input: *css.Parser) Error![]const u8 {
        const ident = try input.expectIdent();
        return ident;
    }

    pub fn toCss(this: *const Ident, comptime W: type, dest: *Printer(W)) PrintErr!void {
        return css.serializer.serializeIdentifier(this.*, W, dest);
    }
};

pub const CustomIdent = []const u8;
pub const CustomIdentFns = struct {
    pub fn parse(input: *css.Parser) Error!CustomIdent {
        const location = input.currentSourceLocation();
        const ident = try input.expectIdent();
        // css.todo_stuff.match_ignore_ascii_case
        const valid = !(bun.strings.eqlCaseInsensitiveASCIIICheckLength(ident, "initial") or
            bun.strings.eqlCaseInsensitiveASCIIICheckLength(ident, "inherit") or
            bun.strings.eqlCaseInsensitiveASCIIICheckLength(ident, "unset") or
            bun.strings.eqlCaseInsensitiveASCIIICheckLength(ident, "default") or
            bun.strings.eqlCaseInsensitiveASCIIICheckLength(ident, "revert") or
            bun.strings.eqlCaseInsensitiveASCIIICheckLength(ident, "revert-layer"));

        if (!valid) return location.newUnexpectedTokenError(.{ .ident = ident });
        return ident;
    }

    const This = @This();

    pub fn toCss(this: *const CustomIdent, comptime W: type, dest: *Printer(W)) PrintErr!void {
        return @This().toCssWithOptions(this, W, dest, true);
    }

    /// Write the custom ident to CSS.
    pub fn toCssWithOptions(
        this: *const CustomIdent,
        comptime W: type,
        dest: *Printer(W),
        enabled_css_modules: bool,
    ) PrintErr!void {
        const css_module_custom_idents_enabled = enabled_css_modules and
            if (dest.css_module) |*css_module|
            css_module.config.custom_idents
        else
            false;
        return dest.writeIdent(this.*, css_module_custom_idents_enabled);
    }
};

/// A list of CSS [`<custom-ident>`](https://www.w3.org/TR/css-values-4/#custom-idents) values.
pub const CustomIdentList = css.SmallList(CustomIdent, 1);