const std = @import("std");
const bun = @import("root").bun;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayListUnmanaged;

pub const css = @import("../css_parser.zig");

const SmallList = css.SmallList;
const Printer = css.Printer;
const PrintErr = css.PrintErr;
const Error = css.Error;

const ContainerName = css.css_rules.container.ContainerName;

const LengthPercentage = css.css_values.length.LengthPercentage;
const CustomIdent = css.css_values.ident.CustomIdent;
const CSSString = css.css_values.string.CSSString;
const CSSNumber = css.css_values.number.CSSNumber;
const LengthPercentageOrAuto = css.css_values.length.LengthPercentageOrAuto;
const Size2D = css.css_values.size.Size2D;
const DashedIdent = css.css_values.ident.DashedIdent;
const Image = css.css_values.image.Image;
const CssColor = css.css_values.color.CssColor;
const Ratio = css.css_values.ratio.Ratio;
const Length = css.css_values.length.LengthValue;
const Rect = css.css_values.rect.Rect;
const NumberOrPercentage = css.css_values.percentage.NumberOrPercentage;
const CustomIdentList = css.css_values.ident.CustomIdentList;
const Angle = css.css_values.angle.Angle;
const Url = css.css_values.url.Url;

const GenericBorder = css.css_properties.border.GenericBorder;
const LineStyle = css.css_properties.border.LineStyle;

/// A value for the [overflow](https://www.w3.org/TR/css-overflow-3/#overflow-properties) shorthand property.
pub const Overflow = css.DefineEnumProperty(@compileError(css.todo_stuff.depth));
/// An [overflow](https://www.w3.org/TR/css-overflow-3/#overflow-properties) keyword
/// as used in the `overflow-x`, `overflow-y`, and `overflow` properties.
pub const OverflowKeyword = css.DefineEnumProperty(@compileError(css.todo_stuff.depth));
/// A value for the [text-overflow](https://www.w3.org/TR/css-overflow-3/#text-overflow) property.
pub const TextOverflow = css.DefineEnumProperty(@compileError(css.todo_stuff.depth));