const std = @import("std");
const bun = @import("root").bun;
pub const css = @import("../css_parser.zig");
const Error = css.Error;
const ArrayList = std.ArrayListUnmanaged;
const Printer = css.Printer;
const PrintErr = css.PrintErr;
const CSSNumber = css.css_values.number.CSSNumber;
const CSSNumberFns = css.css_values.number.CSSNumberFns;
const Calc = css.css_values.calc.Calc;
const DimensionPercentage = css.css_values.percentage.DimensionPercentage;
const LengthPercentage = css.css_values.length.LengthPercentage;
const Length = css.css_values.length.Length;
const Percentage = css.css_values.percentage.Percentage;
const CssColor = css.css_values.color.CssColor;
const Image = css.css_values.image.Image;
const Url = css.css_values.url.Url;
const CSSInteger = css.css_values.number.CSSInteger;
const CSSIntegerFns = css.css_values.number.CSSIntegerFns;
const Angle = css.css_values.angle.Angle;
const Time = css.css_values.time.Time;
const Resolution = css.css_values.resolution.Resolution;
const CustomIdent = css.css_values.ident.CustomIdent;
const CustomIdentFns = css.css_values.ident.CustomIdentFns;
const Ident = css.css_values.ident.Ident;

/// A CSS [`<ratio>`](https://www.w3.org/TR/css-values-4/#ratios) value,
/// representing the ratio of two numeric values.
pub const Ratio = struct {
    numerator: CSSNumber,
    denominator: CSSNumber,

    pub fn parse(input: *css.Parser) Error!Ratio {
        const first = try CSSNumberFns.parse(input);
        const second = if (input.tryParse(css.Parser.expectDelim, .{'/'})) |_| try CSSNumberFns.parse(input) else 1.0;
        return Ratio{ .numerator = first, .denominator = second };
    }

    /// Parses a ratio where both operands are required.
    pub fn parseRequired(input: *css.Parser) Error!Ratio {
        const first = try CSSNumberFns.parse(input);
        try input.expectDelim('/');
        const second = try CSSNumberFns.parse(input);
        return Ratio{ .numerator = first, .denominator = second };
    }

    pub fn toCss(this: *const @This(), comptime W: type, dest: *Printer(W)) PrintErr!void {
        try CSSNumberFns.toCss(&this.numerator, W, dest);
        if (this.denominator != 1.0) {
            try dest.delim('/', true);
            try CSSNumberFns.toCss(&this.denominator, W, dest);
        }
    }
};