const std = @import("std");
const Allocator = std.mem.Allocator;
const bun = @import("root").bun;
const logger = bun.logger;
const Log = logger.Log;

pub const css = @import("./css_parser.zig");
pub const Error = css.Error;

pub const Printer = css.Printer;
pub const PrintErr = css.PrintErr;

const ArrayList = std.ArrayListUnmanaged;

pub const impl = struct {
    pub const Selectors = struct {
        pub const SelectorImpl = struct {
            pub const AttrValue = css.css_values.string.CSSString;
            pub const Identifier = css.css_values.ident.Ident;
            pub const LocalName = css.css_values.ident.Ident;
            pub const NamespacePrefix = css.css_values.ident.Ident;
            pub const NamespaceUrl = []const u8;
            pub const BorrowedNamespaceUrl = []const u8;
            pub const BorrowedLocalName = css.css_values.ident.Ident;

            pub const NonTSPseudoClass = api.PseudoClass;
            pub const PseudoElement = api.PseudoElement;
            pub const VendorPrefix = css.VendorPrefix;
            pub const ExtraMatchingData = void;
        };
    };
};

pub const api = struct {
    pub const Selector = GenericSelector(impl.Selectors);
    pub const SelectorList = GenericSelectorList(impl.Selectors);

    /// The definition of whitespace per CSS Selectors Level 3 § 4.
    pub const SELECTOR_WHITESPACE: []const u8 = &u8{ ' ', '\t', '\n', '\r', 0x0C };

    pub fn ValidSelectorImpl(comptime T: type) void {
        _ = T.SelectorImpl.ExtraMatchingData;
        _ = T.SelectorImpl.AttrValue;
        _ = T.SelectorImpl.Identifier;
        _ = T.SelectorImpl.LocalName;
        _ = T.SelectorImpl.NamespaceUrl;
        _ = T.SelectorImpl.NamespacePrefix;
        _ = T.SelectorImpl.BorrowedNamespaceUrl;
        _ = T.SelectorImpl.BorrowedLocalName;

        _ = T.SelectorImpl.NonTSsSeudoClass;
        _ = T.SelectorImpl.VendorPrefix;
        _ = T.SelectorImpl.PseudoElement;
    }

    const selector_builder = struct {
        /// Top-level SelectorBuilder struct. This should be stack-allocated by the
        /// consumer and never moved (because it contains a lot of inline data that
        /// would be slow to memmov).
        ///
        /// After instantiation, callers may call the push_simple_selector() and
        /// push_combinator() methods to append selector data as it is encountered
        /// (from left to right). Once the process is complete, callers should invoke
        /// build(), which transforms the contents of the SelectorBuilder into a heap-
        /// allocated Selector and leaves the builder in a drained state.
        pub fn SelectorBuilder(comptime Impl: type) type {
            ValidSelectorImpl(Impl);

            return struct {
                /// The entire sequence of simple selectors, from left to right, without combinators.
                ///
                /// We make this large because the result of parsing a selector is fed into a new
                /// Arc-ed allocation, so any spilled vec would be a wasted allocation. Also,
                /// Components are large enough that we don't have much cache locality benefit
                /// from reserving stack space for fewer of them.
                ///
                /// todo_stuff.smallvec
                simple_selectors: ArrayList(GenericComponent(Impl)),

                /// The combinators, and the length of the compound selector to their left.
                ///
                /// todo_stuff.smallvec
                combinators: ArrayList(struct { Combinator, usize }),

                /// The length of the current compound selector.
                current_len: usize,

                const This = @This();

                pub fn default() This {}

                /// Returns true if combinators have ever been pushed to this builder.
                pub inline fn hasCombinators(this: *This) bool {
                    return this.combinators.items.len > 0;
                }

                /// Completes the current compound selector and starts a new one, delimited
                /// by the given combinator.
                pub inline fn pushCombinator(this: *This, combinator: Combinator) void {
                    this.combinators.append(@compileError(css.todo_stuff.think_about_allocator), .{ combinator, this.current_len }) catch unreachable;
                    this.current_len = 0;
                }

                /// Pushes a simple selector onto the current compound selector.
                pub fn pushSimpleSelector(this: *This, ss: GenericComponent(Impl)) void {
                    bun.assert(!ss.isCombinator());
                    this.simple_selectors.append(@compileError(css.todo_stuff.think_about_allocator), ss) catch unreachable;
                    this.current_len += 1;
                }

                pub fn addNestingPrefix(this: *This) void {
                    this.combinators.insert(@compileError(css.todo_stuff.think_about_allocator), 0, struct { Combinator.descendant, 1 }) catch unreachable;
                    this.simple_selectors.insert(@compileError(css.todo_stuff.think_about_allocator), 0, .nesting);
                }

                /// Consumes the builder, producing a Selector.
                ///
                /// *NOTE*: This will free all allocated memory in the builder
                /// TODO: deallocate unused memory after calling this
                pub fn build(
                    this: *This,
                    parsed_pseudo: bool,
                    parsed_slotted: bool,
                    parsed_part: bool,
                ) struct {
                    specifity_and_flags: SpecifityAndFlags,
                    components: ArrayList(GenericComponent(Impl)),
                } {
                    {
                        @compileError(css.todo_stuff.think_mem_mgmt);
                    }
                    const specifity = compute_specifity(this.simple_selectors.items);
                    var flags = SelectorFlags.empty();
                    // PERF: is it faster to do these ORs all at once
                    if (parsed_pseudo) {
                        flags.has_pseudo = true;
                    }
                    if (parsed_slotted) {
                        flags.has_slotted = true;
                    }
                    if (parsed_part) {
                        flags.has_part = true;
                    }
                    return this.buildWithSpecificityAndFlags(SpecifityAndFlags{ .specificity = specifity, .flags = flags });
                }

                // TODO: make sure this is correct transliteration of the unsafe Rust original
                pub fn buildWithSpecificityAndFlags(this: *This, spec: SpecifityAndFlags) struct {
                    specifity_and_flags: SpecifityAndFlags,
                    components: ArrayList(GenericComponent(Impl)),
                } {
                    const T = GenericComponent(Impl);
                    const rest: []const T, const current: []const T = splitFromEnd(T, this.simple_selectors.items, this.current_len);
                    const combinators = this.combinators.items;
                    defer {
                        // set len from end for this.simple_selectors here
                        this.simple_selectors.items.len = 0;
                        // clear retaining combinators
                        this.combinators.items.len = 0;
                    }

                    var components = ArrayList(T){};

                    var current_simple_selectors_i: usize = 0;
                    var combinator_i: i64 = @intCast(this.combinators.items.len - 1);
                    var rest_of_simple_selectors = rest;
                    var current_simple_selectors = current;

                    while (true) {
                        if (current_simple_selectors_i < current.len) {
                            components.append(
                                @compileError(css.todo_stuff.think_about_allocator),
                                current_simple_selectors[current_simple_selectors_i],
                            ) catch unreachable;
                            current_simple_selectors_i += 1;
                        } else {
                            if (combinator_i >= 0) {
                                const combo: Combinator, const len: usize = combinators[combinator_i];
                                const rest2, const current2 = splitFromEnd(GenericComponent(Impl), rest_of_simple_selectors, len);
                                rest_of_simple_selectors = rest2;
                                current_simple_selectors_i = 0;
                                current_simple_selectors = current2;
                                combinator_i -= 1;
                                components.append(
                                    @compileError(css.todo_stuff.think_about_allocator),
                                    .{ .combinator = combo },
                                ) catch unreachable;
                            }
                            break;
                        }
                    }

                    return .{ .specifity_and_flags = spec, .components = components };
                }

                pub fn splitFromEnd(comptime T: type, s: []const T, at: usize) struct { []const T, []const T } {
                    const midpoint = s.len - at;
                    return .{
                        s[0..midpoint],
                        s[midpoint..],
                    };
                }
            };
        }
    };

    pub const attrs = struct {
        pub fn AttrSelectorWithOptionalNamespace(comptime Impl: type) type {
            return struct {
                namespace: ?NamespaceConstraint(struct {
                    prefix: Impl.SelectorImpl.NamespacePrefix,
                    url: Impl.SelectorImpl.NamespaceUrl,
                }),
                local_name: Impl.SelectorImpl.LocalName,
                local_name_lower: Impl.SelectorImpl.LocalName,
                operation: ParsedAttrSelectorOperation(Impl.SelectorImpl.AttrValue),
                never_matches: bool,
            };
        }

        pub fn NamespaceConstraint(comptime NamespaceUrl: type) type {
            return union(enum) {
                any,
                /// Empty string for no namespace
                specific: NamespaceUrl,
            };
        }

        pub fn ParsedAttrSelectorOperation(comptime AttrValue: type) type {
            return union(enum) {
                exists,
                with_value: struct {
                    operator: AttrSelectorOperator,
                    case_sensitivity: ParsedCaseSensitivity,
                    expected_value: AttrValue,
                },
            };
        }

        pub const AttrSelectorOperator = enum {
            equal,
            includes,
            dash_match,
            prefix,
            substring,
            suffix,
        };

        pub const AttrSelectorOperation = enum {
            equal,
            includes,
            dash_match,
            prefix,
            substring,
            suffix,
        };

        pub const ParsedCaseSensitivity = enum {
            // 's' was specified.
            explicit_case_sensitive,
            // 'i' was specified.
            ascii_case_insensitive,
            // No flags were specified and HTML says this is a case-sensitive attribute.
            case_sensitive,
            // No flags were specified and HTML says this is a case-insensitive attribute.
            ascii_case_insensitive_if_in_html_element,
        };
    };

    pub const Specifity = struct {
        id_selectors: u32 = 0,
        class_like_selectors: u32 = 0,
        element_selectors: u32 = 0,

        const MAX_10BIT: u32 = (1 << 10) - 1;

        pub fn toU32(this: Specifity) u32 {
            return (@min(this.id_selectors, MAX_10BIT) << 20) |
                (@min(this.class_like_selectors, MAX_10BIT) << 10) |
                @min(this.element_selectors, MAX_10BIT);
        }

        pub fn fromU32(value: u32) Specifity {
            bun.assert(value <= MAX_10BIT << 20 | MAX_10BIT << 10 | MAX_10BIT);
            return Specifity{
                .id_selectors = value >> 20,
                .class_like_selectors = (value >> 10) & MAX_10BIT,
                .element_selectors = value & MAX_10BIT,
            };
        }

        pub fn add(lhs: *Specifity, rhs: Specifity) void {
            lhs.id_selectors += rhs.id_selectors;
            lhs.element_selectors += rhs.element_selectors;
            lhs.class_like_selectors += rhs.class_like_selectors;
        }
    };

    fn compute_specifity(comptime Impl: type, iter: []const GenericComponent(Impl)) u32 {
        const spec = compute_complex_selector_specifity(Impl, iter);
        return spec.toU32();
    }

    fn compute_complex_selector_specifity(comptime Impl: type, iter: []const GenericComponent(Impl)) Specifity {
        var specifity: Specifity = .{};

        for (iter) |*simple_selector| {
            compute_simple_selector_specifity(Impl, simple_selector, &specifity);
        }
    }

    fn compute_simple_selector_specifity(
        comptime Impl: type,
        simple_selector: *const GenericComponent(Impl),
        specifity: *Specifity,
    ) void {
        switch (simple_selector.*) {
            .combinator => {
                bun.unreachablePanic("Found combinator in simple selectors vector?", .{});
            },
            .part, .pseudo_element, .local_name => {
                specifity.element_selectors += 1;
            },
            .slotted => |selector| {
                specifity.element_selectors += 1;
                // Note that due to the way ::slotted works we only compete with
                // other ::slotted rules, so the above rule doesn't really
                // matter, but we do it still for consistency with other
                // pseudo-elements.
                //
                // See: https://github.com/w3c/csswg-drafts/issues/1915
                specifity.add(selector.specifity());
            },
            .host => |maybe_selector| {
                specifity.class_like_selectors += 1;
                if (maybe_selector) |*selector| {
                    // See: https://github.com/w3c/csswg-drafts/issues/1915
                    specifity.add(selector.specifity());
                }
            },
            .id => {
                specifity.id_selectors += 1;
            },
            .class,
            .attribute_in_no_namespace,
            .attribute_in_no_namespace_exists,
            .attribute_other,
            .root,
            .empty,
            .scope,
            .nth,
            .non_ts_pseudo_class,
            => {
                specifity.class_like_selectors += 1;
            },
            .nth_of => |nth_of_data| {
                // https://drafts.csswg.org/selectors/#specificity-rules:
                //
                //     The specificity of the :nth-last-child() pseudo-class,
                //     like the :nth-child() pseudo-class, combines the
                //     specificity of a regular pseudo-class with that of its
                //     selector argument S.
                specifity.class_like_selectors += 1;
                var max: u32 = 0;
                for (nth_of_data.selectors) |*selector| {
                    max = @max(selector.specifity(), max);
                }
                specifity.add(Specifity.fromU32(max));
            },
            .negation, .is, .any => {
                // https://drafts.csswg.org/selectors/#specificity-rules:
                //
                //     The specificity of an :is() pseudo-class is replaced by the
                //     specificity of the most specific complex selector in its
                //     selector list argument.
                const list: []GenericSelector(Impl) = switch (simple_selector.*) {
                    .negation => |list| list,
                    .is => |list| list,
                    .any => |a| a.selectors,
                    else => unreachable,
                };
                var max: u32 = 0;
                for (list) |*selector| {
                    max = @max(selector.specifity(), max);
                }
                specifity.add(Specifity.fromU32(max));
            },
            .where,
            .has,
            .explicit_universal_type,
            .explicit,
            .any_namespace,
            .explicit_no_namespace,
            .default_namespace,
            .namespace,
            => {
                // Does not affect specifity
            },
            .nesting => {
                // TODO
            },
        }
    }

    const SelectorBuilder = selector_builder.SelectorBuilder;

    /// Build up a Selector.
    /// selector : simple_selector_sequence [ combinator simple_selector_sequence ]* ;
    ///
    /// `Err` means invalid selector.
    fn parse_selector(
        comptime Impl: type,
        parser: *SelectorParser,
        input: *css.Parser,
        state: *SelectorParsingState,
        nesting_requirement: NestingRequirement,
    ) Error!GenericSelector(Impl) {
        if (nesting_requirement == .prefixed) {
            const parser_state = input.state();
            if (!(if (input.expectDelim('&')) |_| true else false)) {
                // todo_stuff.errors
                return input.newCustomError(.missing_nesting_prefix);
            }
            input.reset(&parser_state);
        }

        var builder = selector_builder.SelectorBuilder(Impl).default();
        errdefer {
            @compileError(css.todo_stuff.think_mem_mgmt);
        }

        outer_loop: while (true) {
            // Parse a sequence of simple selectors.
            const empty = try parse_compound_selector(parser, state, input, &builder);
            if (empty) {
                const kind: SelectorParseErrorKind = if (builder.hasCombinators())
                    .dangling_combinator
                else
                    .empty_selector;

                // todo_stuff.errors
                return input.newCustomError(kind);
            }

            if (state.intersects(SelectorParsingState.AFTER_PSEUDO)) {
                break;
            }

            // Parse a combinator
            var combinator: Combinator = undefined;
            var any_whitespace = false;
            while (true) {
                const before_this_token = input.state();
                const tok: *css.Token = input.nextIncludingWhitespace() catch break :outer_loop;
                switch (tok.*) {
                    .whitespace => {
                        any_whitespace = true;
                        continue;
                    },
                    .delim => |d| {
                        switch (d) {
                            '>' => {
                                continue;
                            },
                            '+' => {
                                continue;
                            },
                            '~' => {
                                continue;
                            },
                            '/' => {
                                if (parser.deepCombinatorEnabled()) {
                                    continue;
                                }
                            },
                        }
                    },
                    else => {},
                }

                input.reset(&before_this_token);
                if (any_whitespace) {
                    combinator = .descendant;
                    break;
                } else {
                    break :outer_loop;
                }
            }

            if (!state.allowsCombinators()) {
                return input.newCustomError(.invalid_state);
            }

            builder.pushCombinator(combinator);
        }

        if (!state.contains(SelectorParsingState{ .after_nesting = true })) {
            switch (nesting_requirement) {
                .implicit => {
                    builder.addNestingPrefix();
                },
                .contained, .prefixed => {
                    // todo_stuff.errors
                    return input.newCustomError(SelectorParseErrorKind.missing_nesting_selector);
                },
                else => {},
            }
        }

        const has_pseudo_element = state.intersects(SelectorParsingState{
            .after_pseudo_element = true,
            .after_unknown_pseudo_element = true,
        });
        const slotted = state.intersects(SelectorParsingState{ .after_slotted = true });
        const part = state.intersects(SelectorParsingState{ .after_part = true });
        const result = builder.build(has_pseudo_element, slotted, part);
        return Selector{
            .specifity_and_flags = result.specifity_and_flags,
            .components = result.components,
        };
    }

    /// simple_selector_sequence
    /// : [ type_selector | universal ] [ HASH | class | attrib | pseudo | negation ]*
    /// | [ HASH | class | attrib | pseudo | negation ]+
    ///
    /// `Err(())` means invalid selector.
    /// `Ok(true)` is an empty selector
    fn parse_compound_selector(
        comptime Impl: type,
        parser: *SelectorParser,
        state: *SelectorParsingState,
        input: *css.Parser,
        builder: *SelectorBuilder(Impl),
    ) Error!bool {
        input.skipWhitespace();

        var empty: bool = true;
        if (parser.isNestingAllowed() and if (input.tryParse(css.Parser.expectDelim, .{'&'})) |_| true else false) {
            state.insert(SelectorParsingState{ .after_nesting = true });
            builder.pushSimpleSelector(.nesting);
            empty = false;
        }

        if (try parse_type_selector(Impl, parser, input, state.*, builder)) {
            empty = false;
        }

        while (true) {
            const result: SimpleSelectorParseResult(Impl) = if (try parse_one_simple_selector(Impl, parser, input, state)) |result| result else break;

            if (empty) {
                if (parser.defaultNamespace()) |url| {
                    // If there was no explicit type selector, but there is a
                    // default namespace, there is an implicit "<defaultns>|*" type
                    // selector. Except for :host() or :not() / :is() / :where(),
                    // where we ignore it.
                    //
                    // https://drafts.csswg.org/css-scoping/#host-element-in-tree:
                    //
                    //     When considered within its own shadow trees, the shadow
                    //     host is featureless. Only the :host, :host(), and
                    //     :host-context() pseudo-classes are allowed to match it.
                    //
                    // https://drafts.csswg.org/selectors-4/#featureless:
                    //
                    //     A featureless element does not match any selector at all,
                    //     except those it is explicitly defined to match. If a
                    //     given selector is allowed to match a featureless element,
                    //     it must do so while ignoring the default namespace.
                    //
                    // https://drafts.csswg.org/selectors-4/#matches
                    //
                    //     Default namespace declarations do not affect the compound
                    //     selector representing the subject of any selector within
                    //     a :is() pseudo-class, unless that compound selector
                    //     contains an explicit universal selector or type selector.
                    //
                    //     (Similar quotes for :where() / :not())
                    //
                    const ignore_default_ns = state.intersects(SelectorParsingState{ .skip_default_namespace = true }) or
                        (result == .simple_selector and result.simple_selector == .host);
                    if (!ignore_default_ns) {
                        builder.pushSimpleSelector(.{ .default_namespace = url });
                    }
                }
            }

            empty = false;

            switch (result) {
                .simple_selector => {
                    builder.pushSimpleSelector(result.simple_selector);
                },
                .part_pseudo => {
                    const selector = result.part_pseudo;
                    state.insert(SelectorParsingState{ .after_part = true });
                    builder.pushCombinator(.part);
                    builder.pushSimpleSelector(.{ .slotted = selector });
                },
                .slotted_pseudo => |selector| {
                    state.insert(.{ .after_slotted = true });
                    builder.pushCombinator(.slot_assignment);
                    builder.pushSimpleSelector(.{ .slotted = selector });
                },
                .pseudo_element => |p| {
                    if (!p.isUnknown()) {
                        state.insert(SelectorParsingState{ .after_pseudo_element = true });
                        builder.pushCombinator(.pseudo_element);
                    } else {
                        state.insert(.{ .after_unknown_pseudo_element = true });
                    }

                    if (!p.acceptsStatePseudoClasses()) {
                        state.insert(.{ .after_non_stateful_pseudo_element = true });
                    }

                    if (p.isWebkitScrollbar()) {
                        state.insert(.{ .after_webkit_scrollbar = true });
                    }

                    if (p.isViewTransition()) {
                        state.insert(.{ .after_view_transition = true });
                    }

                    builder.pushSimpleSelector(.{ .pseudo_element = p });
                },
            }
        }

        return empty;
    }

    fn parse_relative_selector(
        comptime Impl: type,
        parser: *SelectorParser,
        input: *css.Parser,
        state: *SelectorParsingState,
        nesting_requirement_: NestingRequirement,
    ) Error!GenericSelector(Impl) {
        // https://www.w3.org/TR/selectors-4/#parse-relative-selector
        var nesting_requirement = nesting_requirement_;
        const s = input.state();

        const combinator: ?Combinator = combinator: {
            switch ((try input.next()).*) {
                .delim => |c| {
                    switch (c) {
                        '>' => break :combinator Combinator.child,
                        '+' => break :combinator Combinator.next_sibling,
                        '~' => break :combinator Combinator.later_sibling,
                        else => {},
                    }
                },
            }
            input.reset(&s);
            break :combinator null;
        };

        const scope: GenericComponent(Impl) = if (nesting_requirement == .implicit) .nesting else .scope;

        if (combinator != null) {
            nesting_requirement = .none;
        }

        var selector = try parse_selector(Impl, parser, input, state, nesting_requirement);
        if (combinator) |wombo_combo| {
            // https://www.w3.org/TR/selectors/#absolutizing
            selector.components.append(
                @compileError(css.todo_stuff.think_about_allocator),
                .{ .combinator = wombo_combo },
            ) catch unreachable;
            selector.components.append(
                @compileError(css.todo_stuff.think_about_allocator),
                scope,
            ) catch unreachable;
        }

        return selector;
    }

    pub fn ValidSelectorParser(comptime T: type) type {
        ValidSelectorImpl(T.SelectorParser.Impl);

        // Whether to parse the `::slotted()` pseudo-element.
        _ = T.SelectorParser.parseSlotted;

        _ = T.SelectorParser.parsePart;

        _ = T.SelectorParser.parseIsAndWhere;

        _ = T.SelectorParser.isAndWhereErrorRecovery;

        _ = T.SelectorParser.parseAnyPrefix;

        _ = T.SelectorParser.parseHost;

        _ = T.SelectorParser.parseNonTsPseudoClass;

        _ = T.SelectorParser.parseNonTsFunctionalPseudoClass;

        _ = T.SelectorParser.parsePseudoElement;

        _ = T.SelectorParser.parseFunctionalPseudoElement;

        _ = T.SelectorParser.defaultNamespace;

        _ = T.SelectorParser.namespaceForPrefix;

        _ = T.SelectorParser.isNestingAllowed;

        _ = T.SelectorParser.deepCombinatorEnabled;
    }

    pub const Direction = css.DefineEnumProperty(struct {
        comptime {
            @compileError(css.todo_stuff.enum_property);
        }
    });

    /// A pseudo class.
    pub const PseudoClass = union(enum) {
        /// https://drafts.csswg.org/selectors-4/#linguistic-pseudos
        /// The [:lang()](https://drafts.csswg.org/selectors-4/#the-lang-pseudo) pseudo class.
        lang: struct {
            /// A list of language codes.
            languages: ArrayList([]const u8),
        },
        /// The [:dir()](https://drafts.csswg.org/selectors-4/#the-dir-pseudo) pseudo class.
        dir: struct {
            /// A direction.
            direction: Direction,
        },

        // https://drafts.csswg.org/selectors-4/#useraction-pseudos
        /// The [:hover](https://drafts.csswg.org/selectors-4/#the-hover-pseudo) pseudo class.
        hover,
        /// The [:active](https://drafts.csswg.org/selectors-4/#the-active-pseudo) pseudo class.
        active,
        /// The [:focus](https://drafts.csswg.org/selectors-4/#the-focus-pseudo) pseudo class.
        focus,
        /// The [:focus-visible](https://drafts.csswg.org/selectors-4/#the-focus-visible-pseudo) pseudo class.
        focus_visible,
        /// The [:focus-within](https://drafts.csswg.org/selectors-4/#the-focus-within-pseudo) pseudo class.
        focus_within,

        /// https://drafts.csswg.org/selectors-4/#time-pseudos
        /// The [:current](https://drafts.csswg.org/selectors-4/#the-current-pseudo) pseudo class.
        current,
        /// The [:past](https://drafts.csswg.org/selectors-4/#the-past-pseudo) pseudo class.
        past,
        /// The [:future](https://drafts.csswg.org/selectors-4/#the-future-pseudo) pseudo class.
        future,

        /// https://drafts.csswg.org/selectors-4/#resource-pseudos
        /// The [:playing](https://drafts.csswg.org/selectors-4/#selectordef-playing) pseudo class.
        playing,
        /// The [:paused](https://drafts.csswg.org/selectors-4/#selectordef-paused) pseudo class.
        paused,
        /// The [:seeking](https://drafts.csswg.org/selectors-4/#selectordef-seeking) pseudo class.
        seeking,
        /// The [:buffering](https://drafts.csswg.org/selectors-4/#selectordef-buffering) pseudo class.
        buffering,
        /// The [:stalled](https://drafts.csswg.org/selectors-4/#selectordef-stalled) pseudo class.
        stalled,
        /// The [:muted](https://drafts.csswg.org/selectors-4/#selectordef-muted) pseudo class.
        muted,
        /// The [:volume-locked](https://drafts.csswg.org/selectors-4/#selectordef-volume-locked) pseudo class.
        volume_locked,

        /// The [:fullscreen](https://fullscreen.spec.whatwg.org/#:fullscreen-pseudo-class) pseudo class.
        fullscreen: css.VendorPrefix,

        /// https://drafts.csswg.org/selectors/#display-state-pseudos
        /// The [:open](https://drafts.csswg.org/selectors/#selectordef-open) pseudo class.
        open,
        /// The [:closed](https://drafts.csswg.org/selectors/#selectordef-closed) pseudo class.
        closed,
        /// The [:modal](https://drafts.csswg.org/selectors/#modal-state) pseudo class.
        modal,
        /// The [:picture-in-picture](https://drafts.csswg.org/selectors/#pip-state) pseudo class.
        picture_in_picture,

        /// https://html.spec.whatwg.org/multipage/semantics-other.html#selector-popover-open
        /// The [:popover-open](https://html.spec.whatwg.org/multipage/semantics-other.html#selector-popover-open) pseudo class.
        popover_open,

        /// The [:defined](https://drafts.csswg.org/selectors-4/#the-defined-pseudo) pseudo class.
        defined,

        /// https://drafts.csswg.org/selectors-4/#location
        /// The [:any-link](https://drafts.csswg.org/selectors-4/#the-any-link-pseudo) pseudo class.
        any_link: css.VendorPrefix,
        /// The [:link](https://drafts.csswg.org/selectors-4/#link-pseudo) pseudo class.
        link,
        /// The [:local-link](https://drafts.csswg.org/selectors-4/#the-local-link-pseudo) pseudo class.
        local_link,
        /// The [:target](https://drafts.csswg.org/selectors-4/#the-target-pseudo) pseudo class.
        target,
        /// The [:target-within](https://drafts.csswg.org/selectors-4/#the-target-within-pseudo) pseudo class.
        taget_within,
        /// The [:visited](https://drafts.csswg.org/selectors-4/#visited-pseudo) pseudo class.
        visited,

        /// https://drafts.csswg.org/selectors-4/#input-pseudos
        /// The [:enabled](https://drafts.csswg.org/selectors-4/#enabled-pseudo) pseudo class.
        enabled,
        /// The [:disabled](https://drafts.csswg.org/selectors-4/#disabled-pseudo) pseudo class.
        disabled,
        /// The [:read-only](https://drafts.csswg.org/selectors-4/#read-only-pseudo) pseudo class.
        read_only: css.VendorPrefix,
        /// The [:read-write](https://drafts.csswg.org/selectors-4/#read-write-pseudo) pseudo class.
        read_write: css.VendorPrefix,
        /// The [:placeholder-shown](https://drafts.csswg.org/selectors-4/#placeholder) pseudo class.
        placeholder_shown: css.VendorPrefix,
        /// The [:default](https://drafts.csswg.org/selectors-4/#the-default-pseudo) pseudo class.
        default,
        /// The [:checked](https://drafts.csswg.org/selectors-4/#checked) pseudo class.
        checked,
        /// The [:indeterminate](https://drafts.csswg.org/selectors-4/#indeterminate) pseudo class.
        indeterminate,
        /// The [:blank](https://drafts.csswg.org/selectors-4/#blank) pseudo class.
        blank,
        /// The [:valid](https://drafts.csswg.org/selectors-4/#valid-pseudo) pseudo class.
        valid,
        /// The [:invalid](https://drafts.csswg.org/selectors-4/#invalid-pseudo) pseudo class.
        invalid,
        /// The [:in-range](https://drafts.csswg.org/selectors-4/#in-range-pseudo) pseudo class.
        in_range,
        /// The [:out-of-range](https://drafts.csswg.org/selectors-4/#out-of-range-pseudo) pseudo class.
        out_of_range,
        /// The [:required](https://drafts.csswg.org/selectors-4/#required-pseudo) pseudo class.
        required,
        /// The [:optional](https://drafts.csswg.org/selectors-4/#optional-pseudo) pseudo class.
        optional,
        /// The [:user-valid](https://drafts.csswg.org/selectors-4/#user-valid-pseudo) pseudo class.
        user_valid,
        /// The [:used-invalid](https://drafts.csswg.org/selectors-4/#user-invalid-pseudo) pseudo class.
        user_invalid,

        /// The [:autofill](https://html.spec.whatwg.org/multipage/semantics-other.html#selector-autofill) pseudo class.
        autofill: css.VendorPrefix,

        // CSS modules
        /// The CSS modules :local() pseudo class.
        local: struct {
            /// A local selector.
            selector: *Selector,
        },
        /// The CSS modules :global() pseudo class.
        global: struct {
            /// A global selector.
            selector: *Selector,
        },

        /// A [webkit scrollbar](https://webkit.org/blog/363/styling-scrollbars/) pseudo class.
        // https://webkit.org/blog/363/styling-scrollbars/
        webkit_scrollbar: WebKitScrollbarPseudoClass,
        /// An unknown pseudo class.
        custom: struct {
            /// The pseudo class name.
            name: []const u8,
        },
        /// An unknown functional pseudo class.
        custom_function: struct {
            /// The pseudo class name.
            name: []const u8,
            /// The arguments of the pseudo class function.
            arguments: css.TokenList,
        },
    };

    /// A [webkit scrollbar](https://webkit.org/blog/363/styling-scrollbars/) pseudo class.
    pub const WebKitScrollbarPseudoClass = enum {
        /// :horizontal
        horizontal,
        /// :vertical
        vertical,
        /// :decrement
        decrement,
        /// :increment
        increment,
        /// :start
        start,
        /// :end
        end,
        /// :double-button
        double_button,
        /// :single-button
        single_button,
        /// :no-button
        no_button,
        /// :corner-present
        corner_present,
        /// :window-inactive
        window_inactive,
    };

    /// A [webkit scrollbar](https://webkit.org/blog/363/styling-scrollbars/) pseudo element.
    pub const WebKitScrollbarPseudoElement = enum {
        /// ::-webkit-scrollbar
        scrollbar,
        /// ::-webkit-scrollbar-button
        button,
        /// ::-webkit-scrollbar-track
        track,
        /// ::-webkit-scrollbar-track-piece
        track_piece,
        /// ::-webkit-scrollbar-thumb
        thumb,
        /// ::-webkit-scrollbar-corner
        corner,
        /// ::-webkit-resizer
        resizer,
    };

    pub const SelectorParser = struct {
        is_nesting_allowed: bool,
        options: *const css.ParserOptions,

        pub const Impl = impl.Selectors;

        pub fn namespaceForPrefix(this: *SelectorParser, prefix: css.css_values.ident.Ident) ?[]const u8 {
            _ = this; // autofix
            return prefix;
        }

        pub fn parseNonTsPseudoClass(
            this: *SelectorParser,
            loc: css.SourceLocation,
            name: []const u8,
        ) Error!PseudoClass {
            // @compileError(css.todo_stuff.match_ignore_ascii_case);
            const pseudo_class: PseudoClass = pseudo_class: {
                if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "hover")) {
                    // https://drafts.csswg.org/selectors-4/#useraction-pseudos
                    break :pseudo_class .hover;
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "active")) {
                    // https://drafts.csswg.org/selectors-4/#useraction-pseudos
                    break :pseudo_class .active;
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "focus")) {
                    // https://drafts.csswg.org/selectors-4/#useraction-pseudos
                    break :pseudo_class .focus;
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "focus-visible")) {
                    // https://drafts.csswg.org/selectors-4/#useraction-pseudos
                    break :pseudo_class .focus_visible;
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "focus-within")) {
                    // https://drafts.csswg.org/selectors-4/#useraction-pseudos
                    break :pseudo_class .focus_within;
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "current")) {
                    // https://drafts.csswg.org/selectors-4/#time-pseudos
                    break :pseudo_class .current;
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "past")) {
                    // https://drafts.csswg.org/selectors-4/#time-pseudos
                    break :pseudo_class .past;
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "future")) {
                    // https://drafts.csswg.org/selectors-4/#time-pseudos
                    break :pseudo_class .future;
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "playing")) {
                    // https://drafts.csswg.org/selectors-4/#resource-pseudos
                    break :pseudo_class .playing;
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "paused")) {
                    // https://drafts.csswg.org/selectors-4/#resource-pseudos
                    break :pseudo_class .paused;
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "seeking")) {
                    // https://drafts.csswg.org/selectors-4/#resource-pseudos
                    break :pseudo_class .seeking;
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "buffering")) {
                    // https://drafts.csswg.org/selectors-4/#resource-pseudos
                    break :pseudo_class .buffering;
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "stalled")) {
                    // https://drafts.csswg.org/selectors-4/#resource-pseudos
                    break :pseudo_class .stalled;
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "muted")) {
                    // https://drafts.csswg.org/selectors-4/#resource-pseudos
                    break :pseudo_class .muted;
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "volume-locked")) {
                    // https://drafts.csswg.org/selectors-4/#resource-pseudos
                    break :pseudo_class .volume_locked;
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "fullscreen")) {
                    // https://fullscreen.spec.whatwg.org/#:fullscreen-pseudo-class
                    break :pseudo_class .{ .fullscreen = .none };
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "-webkit-full-screen")) {
                    // https://fullscreen.spec.whatwg.org/#:fullscreen-pseudo-class
                    break :pseudo_class .{ .fullscreen = .webkit };
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "-moz-full-screen")) {
                    // https://fullscreen.spec.whatwg.org/#:fullscreen-pseudo-class
                    break :pseudo_class .{ .fullscreen = .moz_document };
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "-ms-fullscreen")) {
                    // https://fullscreen.spec.whatwg.org/#:fullscreen-pseudo-class
                    break :pseudo_class .{ .fullscreen = .ms };
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "open")) {
                    // https://drafts.csswg.org/selectors/#display-state-pseudos
                    break :pseudo_class .open;
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "closed")) {
                    // https://drafts.csswg.org/selectors/#display-state-pseudos
                    break :pseudo_class .closed;
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "modal")) {
                    // https://drafts.csswg.org/selectors/#display-state-pseudos
                    break :pseudo_class .modal;
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "picture-in-picture")) {
                    // https://drafts.csswg.org/selectors/#display-state-pseudos
                    break :pseudo_class .picture_in_picture;
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "popover-open")) {
                    // https://html.spec.whatwg.org/multipage/semantics-other.html#selector-popover-open
                    break :pseudo_class .popover_open;
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "defined")) {
                    // https://drafts.csswg.org/selectors-4/#the-defined-pseudo
                    break :pseudo_class .defined;
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "any-link")) {
                    // https://drafts.csswg.org/selectors-4/#location
                    break :pseudo_class .{ .any_link = .none };
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "-webkit-any-link")) {
                    // https://drafts.csswg.org/selectors-4/#location
                    break :pseudo_class .{ .any_link = .webkit };
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "-moz-any-link")) {
                    // https://drafts.csswg.org/selectors-4/#location
                    break :pseudo_class .{ .any_link = .moz };
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "link")) {
                    // https://drafts.csswg.org/selectors-4/#location
                    break :pseudo_class .link;
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "local-link")) {
                    // https://drafts.csswg.org/selectors-4/#location
                    break :pseudo_class .local_link;
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "target")) {
                    // https://drafts.csswg.org/selectors-4/#location
                    break :pseudo_class .target;
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "target-within")) {
                    // https://drafts.csswg.org/selectors-4/#location
                    break :pseudo_class .target_within;
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "visited")) {
                    // https://drafts.csswg.org/selectors-4/#location
                    break :pseudo_class .visited;
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "enabled")) {
                    // https://drafts.csswg.org/selectors-4/#input-pseudos
                    break :pseudo_class .enabled;
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "disabled")) {
                    // https://drafts.csswg.org/selectors-4/#input-pseudos
                    break :pseudo_class .disabled;
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "read-only")) {
                    // https://drafts.csswg.org/selectors-4/#input-pseudos
                    break :pseudo_class .{ .read_only = .none };
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "-moz-read-only")) {
                    // https://drafts.csswg.org/selectors-4/#input-pseudos
                    break :pseudo_class .{ .read_only = .moz };
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "read-write")) {
                    // https://drafts.csswg.org/selectors-4/#input-pseudos
                    break :pseudo_class .{ .read_write = .none };
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "-moz-read-write")) {
                    // https://drafts.csswg.org/selectors-4/#input-pseudos
                    break :pseudo_class .{ .read_write = .moz };
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "placeholder-shown")) {
                    // https://drafts.csswg.org/selectors-4/#input-pseudos
                    break :pseudo_class .{ .placeholder_shown = .none };
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "-moz-placeholder-shown")) {
                    // https://drafts.csswg.org/selectors-4/#input-pseudos
                    break :pseudo_class .{ .placeholder_shown = .moz };
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "-ms-placeholder-shown")) {
                    // https://drafts.csswg.org/selectors-4/#input-pseudos
                    break :pseudo_class .{ .placeholder_shown = .ms };
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "default")) {
                    // https://drafts.csswg.org/selectors-4/#input-pseudos
                    break :pseudo_class .default;
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "checked")) {
                    // https://drafts.csswg.org/selectors-4/#input-pseudos
                    break :pseudo_class .checked;
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "indeterminate")) {
                    // https://drafts.csswg.org/selectors-4/#input-pseudos
                    break :pseudo_class .indeterminate;
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "blank")) {
                    // https://drafts.csswg.org/selectors-4/#input-pseudos
                    break :pseudo_class .blank;
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "valid")) {
                    // https://drafts.csswg.org/selectors-4/#input-pseudos
                    break :pseudo_class .valid;
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "invalid")) {
                    // https://drafts.csswg.org/selectors-4/#input-pseudos
                    break :pseudo_class .invalid;
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "in-range")) {
                    // https://drafts.csswg.org/selectors-4/#input-pseudos
                    break :pseudo_class .in_range;
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "out-of-range")) {
                    // https://drafts.csswg.org/selectors-4/#input-pseudos
                    break :pseudo_class .out_of_range;
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "required")) {
                    // https://drafts.csswg.org/selectors-4/#input-pseudos
                    break :pseudo_class .required;
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "optional")) {
                    // https://drafts.csswg.org/selectors-4/#input-pseudos
                    break :pseudo_class .optional;
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "user-valid")) {
                    // https://drafts.csswg.org/selectors-4/#input-pseudos
                    break :pseudo_class .user_valid;
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "user-invalid")) {
                    // https://drafts.csswg.org/selectors-4/#input-pseudos
                    break :pseudo_class .user_invalid;
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "autofill")) {
                    // https://html.spec.whatwg.org/multipage/semantics-other.html#selector-autofill
                    break :pseudo_class .{ .autofill = .none };
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "-webkit-autofill")) {
                    // https://html.spec.whatwg.org/multipage/semantics-other.html#selector-autofill
                    break :pseudo_class .{ .autofill = .webkit };
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "-o-autofill")) {
                    // https://html.spec.whatwg.org/multipage/semantics-other.html#selector-autofill
                    break :pseudo_class .{ .autofill = .o };
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "horizontal")) {
                    // https://webkit.org/blog/363/styling-scrollbars/
                    break :pseudo_class .{ .webkit_scrollbar = .horizontal };
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "vertical")) {
                    // https://webkit.org/blog/363/styling-scrollbars/
                    break :pseudo_class .{ .webkit_scrollbar = .vertical };
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "decrement")) {
                    // https://webkit.org/blog/363/styling-scrollbars/
                    break :pseudo_class .{ .webkit_scrollbar = .decrement };
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "increment")) {
                    // https://webkit.org/blog/363/styling-scrollbars/
                    break :pseudo_class .{ .webkit_scrollbar = .increment };
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "start")) {
                    // https://webkit.org/blog/363/styling-scrollbars/
                    break :pseudo_class .{ .webkit_scrollbar = .start };
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "end")) {
                    // https://webkit.org/blog/363/styling-scrollbars/
                    break :pseudo_class .{ .webkit_scrollbar = .end };
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "double-button")) {
                    // https://webkit.org/blog/363/styling-scrollbars/
                    break :pseudo_class .{ .webkit_scrollbar = .double_button };
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "single-button")) {
                    // https://webkit.org/blog/363/styling-scrollbars/
                    break :pseudo_class .{ .webkit_scrollbar = .single_button };
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "no-button")) {
                    // https://webkit.org/blog/363/styling-scrollbars/
                    break :pseudo_class .{ .webkit_scrollbar = .no_button };
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "corner-present")) {
                    // https://webkit.org/blog/363/styling-scrollbars/
                    break :pseudo_class .{ .webkit_scrollbar = .corner_present };
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "window-inactive")) {
                    // https://webkit.org/blog/363/styling-scrollbars/
                    break :pseudo_class .{ .webkit_scrollbar = .window_inactive };
                } else {
                    if (bun.strings.startsWithChar(name, '_')) {
                        this.options.warn(loc.newCustomError(SelectorParseErrorKind{ .unsupported_pseudo_class_or_element = name }));
                    }
                    return PseudoClass{ .custom = name };
                }
            };

            return pseudo_class;
        }

        pub fn parseNonTsFunctionalPseudoClass(
            this: *SelectorParser,
            name: []const u8,
            parser: *css.Parser,
        ) Error!PseudoClass {

            // todo_stuff.match_ignore_ascii_case
            const pseudo_class = pseudo_class: {
                if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "lang")) {
                    const languages = try parser.parseCommaSeparated([]const u8, css.Parser.expectIdentOrString);
                    return PseudoClass{
                        .lang = .{ .languages = languages },
                    };
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "dir")) {
                    break :pseudo_class PseudoClass{
                        .dir = .{
                            .direction = try Direction.parse(parser),
                        },
                    };
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "local") and this.options.css_modules != null) {
                    break :pseudo_class PseudoClass{
                        .local = .{
                            .selector = brk: {
                                const selector = try Selector.parse();
                                const alloc: Allocator = {
                                    @compileError(css.todo_stuff.think_about_allocator);
                                };

                                const sel = alloc.create(Selector) catch unreachable;
                                sel.* = selector;
                                break :brk sel;
                            },
                        },
                    };
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "global") and this.options.css_modules != null) {
                    break :pseudo_class PseudoClass{
                        .global = .{
                            .selector = brk: {
                                const selector = try Selector.parse();
                                const alloc: Allocator = {
                                    @compileError(css.todo_stuff.think_about_allocator);
                                };

                                const sel = alloc.create(Selector) catch unreachable;
                                sel.* = selector;
                                break :brk sel;
                            },
                        },
                    };
                } else {
                    if (!bun.strings.startsWithChar(name, '-')) {
                        this.options.warn(parser.newCustomError(SelectorParseErrorKind{ .unsupported_pseudo_class_or_element = name }));
                    }
                    var args = ArrayList(css.css_properties.custom.TokenOrValue){};
                    _ = try css.TokenListFns.parseRaw(parser, &args, this.options, 0);
                    break :pseudo_class PseudoClass{
                        .custom_function = .{
                            .name = name,
                            .arguments = args,
                        },
                    };
                }
            };

            return pseudo_class;
        }

        pub fn isNestingAllowed(this: *SelectorParser) bool {
            return this.is_nesting_allowed;
        }

        pub fn deepCombinatorEnabled(this: *SelectorParser) bool {
            return this.options.flags.contains(css.ParserFlags{ .deep_selector_combinator = true });
        }

        pub fn defaultNamespace(this: *SelectorParser) ?impl.Selectors.SelectorImpl.NamespaceUrl {
            _ = this; // autofix
            return null;
        }

        pub fn parsePart(this: *SelectorParser) bool {
            _ = this; // autofix
            return true;
        }

        pub fn parseSlotted(this: *SelectorParser) bool {
            _ = this; // autofix
            return true;
        }

        /// The error recovery that selector lists inside :is() and :where() have.
        fn isAndWhereErrorRecovery(this: *SelectorParser) ParseErrorRecovery {
            _ = this; // autofix
            return .ignore_invalid_selector;
        }

        pub fn parsePseudoElement(this: *SelectorParser, loc: css.SourceLocation, name: []const u8) Error!PseudoElement {
            const pseudo_element: PseudoElement = pseudo_element: {
                if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "before")) {
                    break :pseudo_element .before;
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "after")) {
                    break :pseudo_element .after;
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "first-line")) {
                    break :pseudo_element .first_line;
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "first-letter")) {
                    break :pseudo_element .first_letter;
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "cue")) {
                    break :pseudo_element .cue;
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "cue-region")) {
                    break :pseudo_element .cue_region;
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "selection")) {
                    break :pseudo_element .{ .selection = .none };
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "-moz-selection")) {
                    break :pseudo_element .{ .selection = .moz };
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "placeholder")) {
                    break :pseudo_element .{ .placeholder = .none };
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "-webkit-input-placeholder")) {
                    break :pseudo_element .{ .placeholder = .webkit };
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "-moz-placeholder")) {
                    break :pseudo_element .{ .placeholder = .moz };
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "-ms-input-placeholder")) {
                    // this is a bugin hte source
                    break :pseudo_element .{ .placeholder = .ms };
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "marker")) {
                    break :pseudo_element .maker;
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "backdrop")) {
                    break :pseudo_element .{ .backdrop = .none };
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "-webkit-backdrop")) {
                    break :pseudo_element .{ .backdrop = .webkit };
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "file-selector-button")) {
                    break :pseudo_element .{ .file_selector_button = .none };
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "-webkit-file-upload-button")) {
                    break :pseudo_element .{ .file_selector_button = .webkit };
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "-ms-browse")) {
                    break :pseudo_element .{ .file_selector_button = .ms };
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "-webkit-scrollbar")) {
                    break :pseudo_element .{ .webkit_scrollbar = .scrollbar };
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "-webkit-scrollbar-button")) {
                    break :pseudo_element .{ .webkit_scrollbar = .button };
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "-webkit-scrollbar-track")) {
                    break :pseudo_element .{ .webkit_scrollbar = .track };
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "-webkit-scrollbar-track-piece")) {
                    break :pseudo_element .{ .webkit_scrollbar = .track_piece };
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "-webkit-scrollbar-thumb")) {
                    break :pseudo_element .{ .webkit_scrollbar = .thumb };
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "-webkit-scrollbar-corner")) {
                    break :pseudo_element .{ .webkit_scrollbar = .corner };
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "-webkit-resizer")) {
                    break :pseudo_element .{ .webkit_scrollbar = .resizer };
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "view-transition")) {
                    break :pseudo_element .view_transition;
                } else {
                    if (bun.strings.startsWith(name, '-')) {
                        this.options.warn(loc.newCustomError(SelectorParseErrorKind{ .unsupported_pseudo_class_or_element = name }));
                    }
                    return PseudoElement{ .custom = name };
                }
            };

            return pseudo_element;
        }
    };

    pub fn GenericSelectorList(comptime Impl: type) type {
        ValidSelectorImpl(Impl);

        const SelectorT = GenericSelector(Impl);
        return struct {
            // PERF: make this equivalent to SmallVec<[Selector; 1]>
            v: ArrayList(SelectorT) = .{},

            const This = @This();

            pub fn toCss(this: *const This, comptime W: type, dest: *Printer(W)) PrintErr!void {
                _ = this; // autofix
                _ = dest; // autofix
                @compileError(css.todo_stuff.depth);
            }

            pub fn parse(
                parser: *SelectorParser,
                input: *css.Parser,
                error_recovery: ParseErrorRecovery,
                nesting_requirement: NestingRequirement,
            ) Error!This {
                var state = SelectorParsingState.empty();
                return parseWithState(parser, input, &state, error_recovery, nesting_requirement);
            }

            pub fn parseRelative(
                parser: *SelectorParser,
                input: *css.Parser,
                error_recovery: ParseErrorRecovery,
                nesting_requirement: NestingRequirement,
            ) Error!This {
                var state = SelectorParsingState.empty();
                return parseRelativeWithState(parser, input, &state, error_recovery, nesting_requirement);
            }

            pub fn parseWithState(
                parser: *SelectorParser,
                input: *css.Parser,
                state: *SelectorParsingState,
                recovery: ParseErrorRecovery,
                nesting_requirement: NestingRequirement,
            ) Error!This {
                const original_state = state.*;
                // TODO: Think about deinitialization in error cases
                var values = ArrayList(SelectorT){};

                while (true) {
                    const Closure = struct {
                        outer_state: *SelectorParsingState,
                        original_state: SelectorParsingState,
                        nesting_requirement: NestingRequirement,

                        pub fn parsefn(this: *@This(), input2: *css.Parser) Error!SelectorT {
                            var selector_state = this.original_state;
                            const result = parse_selector(Impl, parser, input2, &selector_state, this.nesting_requirement);
                            if (selector_state.after_nesting) {
                                this.outer_state.after_nesting = true;
                            }
                            return result;
                        }
                    };
                    var closure = Closure{
                        .outer_state = state,
                        .original_state = original_state,
                        .nesting_requirement = nesting_requirement,
                    };
                    const selector = input.parseUntilBefore(css.Delimiters{ .comma = true }, SelectorT, &closure, Closure.parsefn);

                    const was_ok = if (selector) true else false;
                    if (selector) |sel| {
                        values.append(comptime {
                            @compileError("TODO: Think about where Allocator comes from");
                        }, sel) catch bun.outOfMemory();
                    } else |e| {
                        switch (recovery) {
                            .discard_list => return e,
                            .ignore_invalid_selector => {},
                        }
                    }

                    while (true) {
                        if (input.next()) |tok| {
                            if (tok == .comma) break;
                            // Shouldn't have got a selector if getting here.
                            bun.debugAssert(!was_ok);
                        }
                        return .{ .v = values };
                    }
                }
            }

            // TODO: this looks exactly the same as `parseWithState()` except it uses `parse_relative_selector()` instead of `parse_selector()`
            pub fn parseRelativeWithState(
                parser: *SelectorParser,
                input: *css.Parser,
                state: *SelectorParsingState,
                recovery: ParseErrorRecovery,
                nesting_requirement: NestingRequirement,
            ) Error!This {
                const original_state = state.*;
                // TODO: Think about deinitialization in error cases
                var values = ArrayList(SelectorT){};

                while (true) {
                    const Closure = struct {
                        outer_state: *SelectorParsingState,
                        original_state: SelectorParsingState,
                        nesting_requirement: NestingRequirement,

                        pub fn parsefn(this: *@This(), input2: *css.Parser) Error!SelectorT {
                            var selector_state = this.original_state;
                            const result = parse_relative_selector(Impl, parser, input2, &selector_state, this.nesting_requirement);
                            if (selector_state.after_nesting) {
                                this.outer_state.after_nesting = true;
                            }
                            return result;
                        }
                    };
                    var closure = Closure{
                        .outer_state = state,
                        .original_state = original_state,
                        .nesting_requirement = nesting_requirement,
                    };
                    const selector = input.parseUntilBefore(css.Delimiters{ .comma = true }, SelectorT, &closure, Closure.parsefn);

                    const was_ok = if (selector) true else false;
                    if (selector) |sel| {
                        values.append(comptime {
                            @compileError("TODO: Think about where Allocator comes from");
                        }, sel) catch bun.outOfMemory();
                    } else |e| {
                        switch (recovery) {
                            .discard_list => return e,
                            .ignore_invalid_selector => {},
                        }
                    }

                    while (true) {
                        if (input.next()) |tok| {
                            if (tok == .comma) break;
                            // Shouldn't have got a selector if getting here.
                            bun.debugAssert(!was_ok);
                        }
                        return .{ .v = values };
                    }
                }
            }

            pub fn fromSelector(allocator: Allocator, selector: GenericSelector(Impl)) This {
                var result = This{};
                result.v.append(allocator, selector) catch unreachable;
                return result;
            }
        };
    }

    pub fn GenericSelector(comptime Impl: type) type {
        ValidSelectorImpl(Impl);

        return struct {
            specifity_and_flags: SpecifityAndFlags,
            components: ArrayList(GenericComponent(Impl)),

            const This = @This();

            pub fn fromComponent(component: GenericComponent(Impl)) This {
                var builder = SelectorBuilder(Impl).default();
                if (component.asCombinator()) |combinator| {
                    builder.pushCombinator(combinator);
                } else {
                    builder.pushSimpleSelector(component);
                }
                const result = builder.build(false, false, false);
                return This{
                    .specifity_and_flags = result.specifity_and_flags,
                    .components = result.components,
                };
            }

            pub fn specifity(this: *const This) u32 {
                this.specifity_and_flags.specificity;
            }

            /// Parse a selector, without any pseudo-element.
            pub fn parse(parser: *SelectorParser, input: *css.Parser) Error!This {
                var state = SelectorParsingState.empty();
                return parse_selector(Impl, parser, input, &state, .none);
            }
        };
    }

    /// A CSS simple selector or combinator. We store both in the same enum for
    /// optimal packing and cache performance, see [1].
    ///
    /// [1] https://bugzilla.mozilla.org/show_bug.cgi?id=1357973
    pub fn GenericComponent(comptime Impl: type) type {
        ValidSelectorImpl(Impl);

        return union(enum) {
            combinator: Combinator,

            explicit_any_namespace,
            explicit_no_namespace,
            default_namespace: Impl.SelectorImpl.NamespaceUrl,
            namespace: struct {
                prefix: Impl.SelectorImpl.NamespacePrefix,
                url: Impl.SelectorImpl.NamespaceUrl,
            },

            explicit_universal_type,
            local_name: LocalName(Impl),

            id: Impl.SelectorImpl.Identifier,
            class: Impl.SelectorImpl.Identifier,

            attribute_in_no_namespace_exists: struct {
                local_name: Impl.SelectorImpl.LocalName,
                local_name_lower: Impl.SelectorImpl.LocalName,
            },
            /// Used only when local_name is already lowercase.
            attribute_in_no_namespace: struct {
                local_name: Impl.SelectorImpl.LocalName,
                operator: attrs.AttrSelectorOperator,
                value: Impl.SelectorImpl.AttrValue,
                case_sensitivity: attrs.ParsedCaseSensitivity,
                never_matches: bool,
            },
            /// Use a Box in the less common cases with more data to keep size_of::<Component>() small.
            attribute_other: *attrs.AttrSelectorWithOptionalNamespace(Impl),

            /// Pseudo-classes
            negation: []GenericSelector(Impl),
            root,
            empty,
            scope,
            nth: NthSelectorData,
            nth_of: NthOfSelectorData(Impl),
            non_ts_pseudo_class: Impl.SelectorImpl.NonTSPseudoClass,
            /// The ::slotted() pseudo-element:
            ///
            /// https://drafts.csswg.org/css-scoping/#slotted-pseudo
            ///
            /// The selector here is a compound selector, that is, no combinators.
            ///
            /// NOTE(emilio): This should support a list of selectors, but as of this
            /// writing no other browser does, and that allows them to put ::slotted()
            /// in the rule hash, so we do that too.
            ///
            /// See https://github.com/w3c/csswg-drafts/issues/2158
            slotted: GenericSelector(Impl),
            /// The `::part` pseudo-element.
            ///   https://drafts.csswg.org/css-shadow-parts/#part
            part: []GenericSelector(Impl.SelectorImpl.Identifier),
            /// The `:host` pseudo-class:
            ///
            /// https://drafts.csswg.org/css-scoping/#host-selector
            ///
            /// NOTE(emilio): This should support a list of selectors, but as of this
            /// writing no other browser does, and that allows them to put :host()
            /// in the rule hash, so we do that too.
            ///
            /// See https://github.com/w3c/csswg-drafts/issues/2158
            host: ?GenericSelector(Impl.SelectorImpl.Identifier),
            /// The `:where` pseudo-class.
            ///
            /// https://drafts.csswg.org/selectors/#zero-matches
            ///
            /// The inner argument is conceptually a SelectorList, but we move the
            /// selectors to the heap to keep Component small.
            where: []GenericSelector(Impl),
            /// The `:is` pseudo-class.
            ///
            /// https://drafts.csswg.org/selectors/#matches-pseudo
            ///
            /// Same comment as above re. the argument.
            is: []GenericSelector(Impl),
            any: struct {
                vendor_prefix: Impl.SelectorImpl.VendorPrefix,
                selectors: []GenericSelector(Impl),
            },
            /// The `:has` pseudo-class.
            ///
            /// https://www.w3.org/TR/selectors/#relational
            has: []GenericSelector(Impl),
            /// An implementation-dependent pseudo-element selector.
            pseudo_element: Impl.SelectorImpl.PseudoElement,
            /// A nesting selector:
            ///
            /// https://drafts.csswg.org/css-nesting-1/#nest-selector
            ///
            /// NOTE: This is a lightningcss addition.
            nesting,

            const This = @This();

            pub fn asCombinator(this: *const This) ?Combinator {
                if (this.* == .combinator) return this.combinator;
                return null;
            }

            pub fn convertHelper_is(s: []GenericSelector(Impl)) This {
                return .{ .is = s };
            }

            pub fn convertHelper_where(s: []GenericSelector(Impl)) This {
                return .{ .where = s };
            }

            pub fn convertHelper_any(s: []GenericSelector(Impl), prefix: Impl.SelectorImpl.VendorPrefix) This {
                return .{
                    .any = .{
                        .vendor_prefix = prefix,
                        .selectors = s,
                    },
                };
            }

            /// Returns true if this is a combinator.
            pub fn isCombinator(this: *This) bool {
                return this.* == .combinator;
            }
        };
    }

    /// The properties that comprise an :nth- pseudoclass as of Selectors 3 (e.g.,
    /// nth-child(An+B)).
    /// https://www.w3.org/TR/selectors-3/#nth-child-pseudo
    pub const NthSelectorData = struct {
        ty: NthType,
        is_function: bool,
        a: i32,
        b: i32,

        /// Returns selector data for :only-{child,of-type}
        pub fn only(of_type: bool) NthSelectorData {
            return NthSelectorData{
                .ty = if (of_type) NthType.only_of_type else NthType.only_child,
                .is_function = false,
                .a = 0,
                .b = 1,
            };
        }

        /// Returns selector data for :first-{child,of-type}
        pub fn first(of_type: bool) NthSelectorData {
            return NthSelectorData{
                .ty = if (of_type) NthType.of_type else NthType.child,
                .is_function = false,
                .a = 0,
                .b = 1,
            };
        }

        /// Returns selector data for :last-{child,of-type}
        pub fn last(of_type: bool) NthSelectorData {
            return NthSelectorData{
                .ty = if (of_type) NthType.last_of_type else NthType.last_child,
                .is_function = false,
                .a = 0,
                .b = 1,
            };
        }
    };

    /// The properties that comprise an :nth- pseudoclass as of Selectors 4 (e.g.,
    /// nth-child(An+B [of S]?)).
    /// https://www.w3.org/TR/selectors-4/#nth-child-pseudo
    pub fn NthOfSelectorData(comptime Impl: type) type {
        return struct {
            data: NthSelectorData,
            selectors: []GenericSelector(Impl),
        };
    }

    pub const SelectorParsingState = packed struct(u16) {
        /// Whether we should avoid adding default namespaces to selectors that
        /// aren't type or universal selectors.
        skip_default_namespace: bool = false,

        /// Whether we've parsed a ::slotted() pseudo-element already.
        ///
        /// If so, then we can only parse a subset of pseudo-elements, and
        /// whatever comes after them if so.
        after_slotted: bool = false,

        /// Whether we've parsed a ::part() pseudo-element already.
        ///
        /// If so, then we can only parse a subset of pseudo-elements, and
        /// whatever comes after them if so.
        after_part: bool = false,

        /// Whether we've parsed a pseudo-element (as in, an
        /// `Impl::PseudoElement` thus not accounting for `::slotted` or
        /// `::part`) already.
        ///
        /// If so, then other pseudo-elements and most other selectors are
        /// disallowed.
        after_pseudo_element: bool = false,

        /// Whether we've parsed a non-stateful pseudo-element (again, as-in
        /// `Impl::PseudoElement`) already. If so, then other pseudo-classes are
        /// disallowed. If this flag is set, `AFTER_PSEUDO_ELEMENT` must be set
        /// as well.
        after_non_stateful_pseudo_element: bool = false,

        /// Whether we explicitly disallow combinators.
        disallow_combinators: bool = false,

        /// Whether we explicitly disallow pseudo-element-like things.
        disallow_pseudos: bool = false,

        /// Whether we have seen a nesting selector.
        after_nesting: bool = false,

        after_webkit_scrollbar: bool = false,
        after_view_transition: bool = false,
        after_unknown_pseudo_element: bool = false,

        /// Whether we are after any of the pseudo-like things.
        pub const AFTER_PSEUDO = css.Bitflags.bitwiseOr(.{
            SelectorParsingState{ .after_part = true },
            SelectorParsingState{ .after_slotted = true },
            SelectorParsingState{ .after_pseudo_element = true },
        });

        pub inline fn empty() SelectorParsingState {
            return .{};
        }

        pub fn intersects(self: SelectorParsingState, other: SelectorParsingState) bool {
            _ = other; // autofix
            _ = self; // autofix
            css.todo("SelectorParsingState.intersects", .{});
        }

        pub fn insert(self: *SelectorParsingState, other: SelectorParsingState) void {
            _ = self; // autofix
            _ = other; // autofix
            css.todo("SelectorParsingState.insert", .{});
        }

        pub fn allowsPseudos(this: SelectorParsingState) bool {
            _ = this; // autofix
            css.todo("SelectorParsingState.allowsPseudos", .{});
        }

        pub fn allowsPart(this: SelectorParsingState) bool {
            _ = this; // autofix
            css.todo("SelectorParsingState.allowsPart", .{});
        }

        pub fn allowsSlotted(this: SelectorParsingState) bool {
            _ = this; // autofix
            css.todo("SelectorParsingState.allowsSlotted", .{});
        }

        pub fn allowsTreeStructuralPseudoClasses(this: SelectorParsingState) bool {
            return !this.intersects(SelectorParsingState.AFTER_PSEUDO);
        }

        pub fn allowsNonFunctionalPseudoClasses(this: SelectorParsingState) bool {
            return !this.intersects(SelectorParsingState{ .after_slotted = true, .after_non_stateful_pseudo_element = true });
        }
    };

    pub const SpecifityAndFlags = struct {
        /// There are two free bits here, since we use ten bits for each specificity
        /// kind (id, class, element).
        specificity: u32,
        /// There's padding after this field due to the size of the flags.
        flags: SelectorFlags,
    };

    pub const SelectorFlags = packed struct(u8) {
        has_pseudo: bool = false,
        has_slotted: bool = false,
        has_part: bool = false,
        __unused: u5 = 0,
    };

    /// How to treat invalid selectors in a selector list.
    pub const ParseErrorRecovery = enum {
        /// Discard the entire selector list, this is the default behavior for
        /// almost all of CSS.
        discard_list,
        /// Ignore invalid selectors, potentially creating an empty selector list.
        ///
        /// This is the error recovery mode of :is() and :where()
        ignore_invalid_selector,
    };

    pub const NestingRequirement = enum {
        none,
        prefixed,
        contained,
        implicit,
    };

    pub const Combinator = enum {
        child, // >
        descendant, // space
        next_sibling, // +
        later_sibling, // ~
        /// A dummy combinator we use to the left of pseudo-elements.
        ///
        /// It serializes as the empty string, and acts effectively as a child
        /// combinator in most cases.  If we ever actually start using a child
        /// combinator for this, we will need to fix up the way hashes are computed
        /// for revalidation selectors.
        pseudo_element,
        /// Another combinator used for ::slotted(), which represent the jump from
        /// a node to its assigned slot.
        slot_assignment,
        /// Another combinator used for `::part()`, which represents the jump from
        /// the part to the containing shadow host.
        part,

        /// Non-standard Vue >>> combinator.
        /// https://vue-loader.vuejs.org/guide/scoped-css.html#deep-selectors
        deep_descendant,
        /// Non-standard /deep/ combinator.
        /// Appeared in early versions of the css-scoping-1 specification:
        /// https://www.w3.org/TR/2014/WD-css-scoping-1-20140403/#deep-combinator
        /// And still supported as an alias for >>> by Vue.
        deep,
    };

    pub const SelectorParseErrorKind = union(enum) {
        invalid_state,
        class_needs_ident: css.Token,
        pseudo_element_expected_ident: css.Token,
        unsupported_pseudo_class_or_element: []const u8,
        no_qualified_name_in_attribute_selector: css.Token,
        unexpected_token_in_attribute_selector: css.Token,
        invalid_qual_name_in_attr: css.Token,
        expected_bar_in_attr: css.Token,
        empty_selector,
        dangling_combinator,
        invalid_pseudo_class_before_webkit_scrollbar,
        invalid_pseudo_class_after_webkit_scrollbar,
        invalid_pseudo_class_after_pseudo_element,
        missing_nesting_selector,
        missing_nesting_prefix,
        expected_namespace: []const u8,
        bad_value_in_attr: css.Token,
        explicit_namespace_unexpected_token: css.Token,
        unexpected_ident: []const u8,
    };

    pub fn SimpleSelectorParseResult(comptime Impl: type) type {
        ValidSelectorImpl(Impl);

        return union(enum) {
            simple_selector: GenericComponent(Impl),
            pseudo_element: Impl.PseudoElement,
            slotted_pseudo: GenericSelector(Impl),
            // todo_stuff.think_mem_mgmt
            part_pseudo: []Impl.Identifier,
        };
    }

    /// A pseudo element.
    pub const PseudoElement = union(enum) {
        /// The [::after](https://drafts.csswg.org/css-pseudo-4/#selectordef-after) pseudo element.
        after,
        /// The [::before](https://drafts.csswg.org/css-pseudo-4/#selectordef-before) pseudo element.
        before,
        /// The [::first-line](https://drafts.csswg.org/css-pseudo-4/#first-line-pseudo) pseudo element.
        first_line,
        /// The [::first-letter](https://drafts.csswg.org/css-pseudo-4/#first-letter-pseudo) pseudo element.
        first_letter,
        /// The [::selection](https://drafts.csswg.org/css-pseudo-4/#selectordef-selection) pseudo element.
        selection: css.VendorPrefix,
        /// The [::placeholder](https://drafts.csswg.org/css-pseudo-4/#placeholder-pseudo) pseudo element.
        placeholder: css.VendorPrefix,
        /// The [::marker](https://drafts.csswg.org/css-pseudo-4/#marker-pseudo) pseudo element.
        marker,
        /// The [::backdrop](https://fullscreen.spec.whatwg.org/#::backdrop-pseudo-element) pseudo element.
        backdrop: css.VendorPrefix,
        /// The [::file-selector-button](https://drafts.csswg.org/css-pseudo-4/#file-selector-button-pseudo) pseudo element.
        file_selector_button: css.VendorPrefix,
        /// A [webkit scrollbar](https://webkit.org/blog/363/styling-scrollbars/) pseudo element.
        webkit_scrollbar: WebKitScrollbarPseudoElement,
        /// The [::cue](https://w3c.github.io/webvtt/#the-cue-pseudo-element) pseudo element.
        cue,
        /// The [::cue-region](https://w3c.github.io/webvtt/#the-cue-region-pseudo-element) pseudo element.
        cue_region,
        /// The [::cue()](https://w3c.github.io/webvtt/#cue-selector) functional pseudo element.
        cue_function: struct {
            /// The selector argument.
            selector: *Selector,
        },
        /// The [::cue-region()](https://w3c.github.io/webvtt/#cue-region-selector) functional pseudo element.
        cue_region_function: struct {
            /// The selector argument.
            selector: *Selector,
        },
        /// The [::view-transition](https://w3c.github.io/csswg-drafts/css-view-transitions-1/#view-transition) pseudo element.
        view_transition,
        /// The [::view-transition-group()](https://w3c.github.io/csswg-drafts/css-view-transitions-1/#view-transition-group-pt-name-selector) functional pseudo element.
        view_transition_group: struct {
            /// A part name selector.
            part_name: ViewTransitionPartName,
        },
        /// The [::view-transition-image-pair()](https://w3c.github.io/csswg-drafts/css-view-transitions-1/#view-transition-image-pair-pt-name-selector) functional pseudo element.
        view_transition_image_pair: struct {
            /// A part name selector.
            part_name: ViewTransitionPartName,
        },
        /// The [::view-transition-old()](https://w3c.github.io/csswg-drafts/css-view-transitions-1/#view-transition-old-pt-name-selector) functional pseudo element.
        view_transition_old: struct {
            /// A part name selector.
            part_name: ViewTransitionPartName,
        },
        /// The [::view-transition-new()](https://w3c.github.io/csswg-drafts/css-view-transitions-1/#view-transition-new-pt-name-selector) functional pseudo element.
        view_transition_new: struct {
            /// A part name selector.
            part_name: ViewTransitionPartName,
        },
        /// An unknown pseudo element.
        custom: struct {
            /// The name of the pseudo element.
            name: []const u8,
        },
        /// An unknown functional pseudo element.
        custom_function: struct {
            /// The name of the pseudo element.
            name: []const u8,
            /// The arguments of the pseudo element function.
            arguments: css.TokenList,
        },

        pub fn acceptsStatePseudoClasses(this: *const PseudoElement) bool {
            _ = this; // autofix
            // Be lienient.
            return true;
        }
    };

    /// An enum for the different types of :nth- pseudoclasses
    pub const NthType = enum {
        child,
        last_child,
        only_child,
        of_type,
        last_of_type,
        only_of_type,
        col,
        last_col,

        pub fn isOnly(self: NthType) bool {
            return self == NthType.only_child or self == NthType.only_of_type;
        }

        pub fn isOfType(self: NthType) bool {
            return self == NthType.of_type or self == NthType.last_of_type or self == NthType.only_of_type;
        }

        pub fn isFromEnd(self: NthType) bool {
            return self == NthType.last_child or self == NthType.last_of_type or self == NthType.last_col;
        }

        pub fn allowsOfSelector(self: NthType) bool {
            return self == NthType.child or self == NthType.last_child;
        }
    };

    /// * `Err(())`: Invalid selector, abort
    /// * `Ok(false)`: Not a type selector, could be something else. `input` was not consumed.
    /// * `Ok(true)`: Length 0 (`*|*`), 1 (`*|E` or `ns|*`) or 2 (`|E` or `ns|E`)
    pub fn parse_type_selector(
        comptime Impl: type,
        parser: *SelectorParser,
        input: *css.Parser,
        state: SelectorParsingState,
        sink: *SelectorBuilder(Impl),
    ) Error!bool {
        const result = parse_qualified_name(
            Impl,
            parser,
            input,
            false,
        ) catch |e| {
            _ = e; // autofix

            // TODO: error does not exist
            // but it should exist
            // todo_stuff.errors
            // if (e == Error.EndOfInput)
            // this is not complete
            // needs to check if error is EndOfInput and return false
            // otherwise return error
            return false;
        };

        if (result == .none) return false;

        const namespace: QNamePrefix(Impl) = result.some[0];
        const local_name: ?[]const u8 = result.some[1];
        if (state.intersects(SelectorParsingState.AFTER_PSEUDO)) {
            return input.newCustomError(SelectorParseErrorKind.invalid_state);
        }

        switch (namespace) {
            .implicit_any_namespace => {},
            .implicit_default_namespace => |url| {
                sink.pushSimpleSelector(.{ .default_namespace = url });
            },
            .explicit_namespace => {
                const prefix = namespace.explicit_namespace[0];
                const url = namespace.explicit_namespace[1];
                const component = component: {
                    if (parser.defaultNamespace()) |default_url| {
                        if (bun.strings.eql(url, default_url)) {
                            break :component .{ .default_namespace = url };
                        }
                    }
                    break :component .{
                        .namespace = .{
                            .prefix = prefix,
                            .url = url,
                        },
                    };
                };
                sink.pushSimpleSelector(component);
            },
            .explicit_no_namespace => {
                sink.pushSimpleSelector(.explicit_no_namespace);
            },
            .explicit_any_namespace => {
                // Element type selectors that have no namespace
                // component (no namespace separator) represent elements
                // without regard to the element's namespace (equivalent
                // to "*|") unless a default namespace has been declared
                // for namespaced selectors (e.g. in CSS, in the style
                // sheet). If a default namespace has been declared,
                // such selectors will represent only elements in the
                // default namespace.
                // -- Selectors § 6.1.1
                // So we'll have this act the same as the
                // QNamePrefix::ImplicitAnyNamespace case.
                // For lightning css this logic was removed, should be handled when matching.
                sink.pushSimpleSelector(.explicit_any_namespace);
            },
            .implicit_no_namespace => {
                bun.unreachablePanic("Should not be returned with in_attr_selector = false", .{});
            },
        }

        if (local_name) |name| {
            sink.pushSimpleSelector(.{
                .local_name = LocalName{
                    .lower_name = brk: {
                        const alloc: std.mem.Allocator = {
                            @compileError(css.todo_stuff.think_about_allocator);
                        };
                        var lowercase = alloc.alloc(u8, name.len) catch unreachable;
                        bun.strings.copyLowercase(name, lowercase[0..]);
                        break :brk lowercase;
                    },
                    .name = name,
                },
            });
        } else {
            sink.pushSimpleSelector(.explicit_universal_type);
        }

        return true;
    }

    /// Parse a simple selector other than a type selector.
    ///
    /// * `Err(())`: Invalid selector, abort
    /// * `Ok(None)`: Not a simple selector, could be something else. `input` was not consumed.
    /// * `Ok(Some(_))`: Parsed a simple selector or pseudo-element
    pub fn parse_one_simple_selector(
        comptime Impl: type,
        parser: *SelectorParser,
        input: *css.Parser,
        state: *SelectorParsingState,
    ) Error!(?SimpleSelectorParseResult(Impl)) {
        const S = SimpleSelectorParseResult(Impl);

        const start = input.state();
        const token = (input.nextIncludingWhitespace() catch {
            input.reset(start);
            return null;
        }).*;

        switch (token) {
            .idhash => |id| {
                if (state.intersects(SelectorParsingState.AFTER_PSEUDO)) {
                    return input.newCustomError(SelectorParseErrorKind.invalid_state);
                }
                const component: GenericComponent(Impl) = .{ .id = id };
                return S{
                    .simple_selector = component,
                };
            },
            .open_square => {
                if (state.intersects(SelectorParsingState.AFTER_PSEUDO)) {
                    return input.newCustomError(SelectorParseErrorKind.invalid_state);
                }
                const Closure = struct {
                    parser: *SelectorParser,
                    pub fn parsefn(this: *@This(), input2: *css.Parser) Error!GenericComponent(Impl) {
                        return try parse_attribute_selector(Impl, this.parser, input2);
                    }
                };
                var closure = Closure{
                    .parser = parser,
                };
                const attr = try input.parseNestedBlock(GenericComponent(Impl), &closure, Closure.parsefn);
                return .{ .simple_selector = attr };
            },
            .colon => {
                const location = input.currentSourceLocation();
                const is_single_colon: bool, const next_token: css.Token = switch ((try input.nextIncludingWhitespace()).*) {
                    .colon => .{ false, (try input.nextIncludingWhitespace()).* },
                    else => |t| .{ true, t },
                };
                const name: []const u8, const is_functional = switch (next_token) {
                    .ident => |name| .{ name, false },
                    .function => |name| .{ name, true },
                    else => |t| {
                        const e = SelectorParseErrorKind{ .pseudo_element_expected_ident = t };
                        return input.newCustomError(e);
                    },
                };
                const is_pseudo_element = !is_single_colon or is_css2_pseudo_element(name);
                if (is_pseudo_element) {
                    if (!state.allowsPseudos()) {
                        return input.newCustomError(SelectorParseErrorKind.invalid_state);
                    }
                    const pseudo_element: Impl.SelectorImpl.PseudoElement = if (is_functional) pseudo_element: {
                        if (parser.parsePart() and bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "part")) {
                            if (!state.allowsPart()) {
                                return input.newCustomError(SelectorParseErrorKind.invalid_state);
                            }

                            const Fn = struct {
                                pub fn parsefn(_: void, input2: *css.Parser) Error![]Impl.SelectorImpl.Identifier {
                                    // todo_stuff.think_about_mem_mgmt
                                    var result = ArrayList(Impl.SelectorImpl.Identifier).initCapacity(
                                        @compileError(css.todo_stuff.think_about_allocator),
                                        // TODO: source does this, should see if initializing to 1 is actually better
                                        // when appending empty std.ArrayList(T), it will usually initially reserve 8 elements,
                                        // maybe that's unnecessary, or maybe smallvec is gud here
                                        1,
                                    ) catch unreachable;

                                    result.append(
                                        @compileError(css.todo_stuff.think_about_allocator),
                                        try input2.expectIdent(),
                                    ) catch unreachable;

                                    while (!input.isExhausted()) {
                                        result.append(
                                            @compileError(css.todo_stuff.think_about_allocator),
                                            try input.expectIdent(),
                                        ) catch unreachable;
                                    }

                                    return result.items;
                                }
                            };

                            const names = try input.parseNestedBlock([]Impl.SelectorImpl.Identifier, {}, Fn.parsefn);

                            break :pseudo_element .{ .part_pseudo = names };
                        }

                        if (parser.parseSlotted() and bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "slotted")) {
                            if (!state.allowsSlotted()) {
                                return input.newCustomError(SelectorParseErrorKind.invalid_state);
                            }
                            const Closure = struct {
                                parser: *SelectorParser,
                                state: *SelectorParsingState,
                                pub fn parsefn(this: *@This(), input2: *css.Parser) Error!GenericSelector(Impl) {
                                    return parse_inner_compound_selector(this.parser, input2, this.state);
                                }
                            };
                            var closure = Closure{
                                .parser = parser,
                                .state = state,
                            };
                            const selector = try input.parseNestedBlock(GenericSelector(Impl), &closure, Closure.parsefn);
                            return .{ .slotted_pseudo = selector };
                        }
                    } else pseudo_element: {
                        break :pseudo_element try parser.parsePseudoElement(location, name);
                    };

                    if (state.intersects(.{ .after_slotted = true }) and pseudo_element.validAfterSlotted()) {
                        return .{ .pseudo_element = pseudo_element };
                    }
                } else {
                    const pseudo_class: GenericComponent(Impl) = if (is_functional) pseudo_class: {
                        const Closure = struct {
                            parser: *SelectorParser,
                            name: []const u8,
                            state: *SelectorParsingState,
                            pub fn parsefn(this: *@This(), input2: *css.Parser) Error!GenericComponent(Impl) {
                                return try parse_functional_pseudo_class(Impl, this.parser, input2, this.name, this.state);
                            }
                        };
                        var closure = Closure{
                            .parser = parser,
                            .name = name,
                            .state = state,
                        };

                        break :pseudo_class try input.parseNestedBlock(GenericComponent(Impl), &closure, Closure.parsefn);
                    } else try parse_simple_pseudo_class(Impl, parser, location, name, state.*);
                    return .{ .simple_selector = pseudo_class };
                }
            },
            .delim => |d| {
                switch (d) {
                    '.' => {
                        if (state.intersects(SelectorParsingState.AFTER_PSEUDO)) {
                            return input.newCustomError(SelectorParseErrorKind.invalid_state);
                        }
                        const location = input.currentSourceLocation();
                        const class = switch ((try input.nextIncludingWhitespace()).*) {
                            .ident => |class| class,
                            else => |t| {
                                const e = SelectorParseErrorKind{ .class_needs_ident = t };
                                return location.newCustomError(e);
                            },
                        };
                        const component_class = .{ .class = class };
                        return .{ .simple_selector = component_class };
                    },
                    '&' => {
                        if (parser.isNestingAllowed()) {
                            state.insert(SelectorParsingState{ .after_nesting = true });
                            return S{
                                .simple_selector = .nesting,
                            };
                        }
                    },
                }
            },
            else => {},
        }

        input.reset(&start);
        return null;
    }

    pub fn parse_attribute_selector(comptime Impl: type, parser: *SelectorParser, input: *css.Parser) Error!GenericComponent(Impl) {
        const alloc: std.mem.Allocator = {
            @compileError(css.todo_stuff.think_about_allocator);
        };

        const N = attrs.NamespaceConstraint(struct {
            prefix: Impl.SelectorImpl.NamespacePrefix,
            url: Impl.SelectorImpl.NamespaceUrl,
        });

        const namespace: ?N, const local_name: []const u8 = brk: {
            input.skipWhitespace();

            switch (try parse_qualified_name(Impl, parser, input, true)) {
                .none => |t| return input.newCustomError(SelectorParseErrorKind{ .no_qualified_name_in_attribute_selector = t }),
                .some => |qname| {
                    if (qname[1] == null) {
                        bun.unreachablePanic("", .{});
                    }
                    const ns: QNamePrefix(Impl) = qname[0];
                    const ln = qname[1].?;
                    break :brk .{
                        switch (ns) {
                            .implicit_no_namespace, .explicit_no_namespace => null,
                            .explicit_namespace => |x| .{ .specific = .{ .prefix = x[0], .url = x[1] } },
                            .explicit_any_namespace => .any,
                            .implicit_any_namespace, .implicit_default_namespace => {
                                bun.unreachablePanic("Not returned with in_attr_selector = true", .{});
                            },
                        },
                        ln,
                    };
                },
            }
        };

        const location = input.currentSourceLocation();
        const operator = operator: {
            const tok = input.next() catch |e| {
                _ = e; // autofix
                const local_name_lower = local_name_lower: {
                    const lower = alloc.alloc(u8, local_name.len) catch unreachable;
                    _ = bun.strings.copyLowercase(local_name, lower);
                    break :local_name_lower lower;
                };
                if (namespace) |ns| {
                    return brk: {
                        const x = attrs.AttrSelectorWithOptionalNamespace(Impl){
                            .namespace = ns,
                            .local_name = local_name,
                            .local_name_lower = local_name_lower,
                            .never_matches = false,
                            .operation = .exists,
                        };
                        const v = alloc.create(@TypeOf(x)) catch unreachable;
                        v.* = x;
                        break :brk v;
                    };
                } else {
                    return .{
                        .attribute_in_no_namespace_exists = .{
                            .local_name = local_name,
                            .local_name_lower = local_name_lower,
                        },
                    };
                }
            };
            switch (tok.*) {
                // [foo=bar]
                .delim => |d| {
                    if (d == '=') break :operator .equal;
                },
                // [foo~=bar]
                .include_match => break :operator .includes,
                // [foo|=bar]
                .dash_match => break :operator .dash_match,
                // [foo^=bar]
                .prefix_match => break :operator .prefix,
                // [foo*=bar]
                .substring_match => break :operator .substring,
                // [foo$=bar]
                .suffix_match => break :operator .suffix,
                else => {},
            }
            return location.newCustomError(SelectorParseErrorKind{ .unexpected_token_in_attribute_selector = tok.* });
        };

        const value_str: []const u8 = (input.expectIdentOrString() catch |e| {
            _ = e; // autofix
            @compileError(css.todo_stuff.errors);
        }).*;
        const never_matches = switch (operator) {
            .equal, .dash_match => false,
            .includes => value_str.len == 0 or std.mem.indexOfAny(u8, value_str, SELECTOR_WHITESPACE),
            .prefix, .substring, .suffix => value_str.len == 0,
        };

        const attribute_flags = try parse_attribute_flags(input);

        const value: Impl.SelectorImpl.AttrValue = value_str;
        const local_name_lower: Impl.SelectorImpl.LocalName, const local_name_is_ascii_lowercase: bool = brk: {
            if (a: {
                for (local_name, 0..) |b, i| {
                    if (b >= 'A' and b <= 'Z') break :a i;
                }
                break :a null;
            }) |first_uppercase| {
                const str = local_name[first_uppercase..];
                const lower = alloc.alloc(u8, str.len) catch unreachable;
                break :brk .{ bun.strings.copyLowercase(str, lower), false };
            } else {
                break :brk .{ local_name, true };
            }
        };
        const case_sensitivity: attrs.ParsedCaseSensitivity = attribute_flags.toCaseSensitivity(local_name_lower, namespace != null);
        if (namespace != null and !local_name_is_ascii_lowercase) {
            return .{
                .attribute_other = brk: {
                    const x = attrs.AttrSelectorWithOptionalNamespace(Impl){
                        .namespace = namespace,
                        .local_name = local_name,
                        .local_name_lower = local_name_lower,
                        .never_matches = never_matches,
                        .operation = .{
                            .with_value = .{
                                .operator = operator,
                                .case_sensitivity = case_sensitivity,
                                .expected_value = value,
                            },
                        },
                    };
                    const v = alloc.create(@TypeOf(x)) catch unreachable;
                    v.* = x;
                    break :brk v;
                },
            };
        } else {
            return .{
                .attribute_in_no_namespace = .{
                    .local_name = local_name,
                    .operator = operator,
                    .value = value,
                    .case_sensitivity = case_sensitivity,
                    .never_matches = never_matches,
                },
            };
        }
    }

    /// Returns whether the name corresponds to a CSS2 pseudo-element that
    /// can be specified with the single colon syntax (in addition to the
    /// double-colon syntax, which can be used for all pseudo-elements).
    pub fn is_css2_pseudo_element(name: []const u8) bool {
        // ** Do not add to this list! **
        // TODO: todo_stuff.match_ignore_ascii_case
        return bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "before") or
            bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "after") or
            bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "first-line") or
            bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "first-letter");
    }

    /// Parses one compound selector suitable for nested stuff like :-moz-any, etc.
    pub fn parse_inner_compound_selector(
        comptime Impl: type,
        parser: *SelectorParser,
        input: *css.Parser,
        state: *SelectorParsingState,
    ) Error!GenericSelector(Impl) {
        var child_state = brk: {
            var child_state = state.*;
            child_state.disallow_pseudos = true;
            child_state.disallow_combinators = true;
            break :brk child_state;
        };
        const result = try parse_selector(Impl, parser, input, &child_state, NestingRequirement.none);
        if (child_state.after_nesting) {
            state.after_nesting = true;
        }
        return result;
    }

    pub fn parse_functional_pseudo_class(
        comptime Impl: type,
        parser: *SelectorParser,
        input: *css.Parser,
        name: []const u8,
        state: *SelectorParsingState,
    ) Error!GenericComponent(Impl) {
        // todo_stuff.match_ignore_ascii_case
        if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "nth-child")) {
            return parse_nth_pseudo_class(Impl, parser, input, state.*, .child);
        } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "nth-of-type")) {
            return parse_nth_pseudo_class(Impl, parser, input, state.*, .of_type);
        } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "nth-last-child")) {
            return parse_nth_pseudo_class(Impl, parser, input, state.*, .last_child);
        } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "nth-last-of-type")) {
            return parse_nth_pseudo_class(Impl, parser, input, state.*, .last_of_type);
        } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "nth-col")) {
            return parse_nth_pseudo_class(Impl, parser, input, state.*, .col);
        } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "nth-last-col")) {
            return parse_nth_pseudo_class(Impl, parser, input, state.*, .last_col);
        } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "is") and parser.parseIsAndWhere()) {
            return parse_is_or_where(Impl, parser, input, state.*, GenericComponent(Impl).convertHelper_is, .{});
        } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "where") and parser.parseIsAndWhere()) {
            return parse_is_or_where(Impl, parser, input, state.*, GenericComponent(Impl).convertHelper_where, .{});
        } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "has")) {
            return parse_has(Impl, parser, input, state);
        } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "host")) {
            if (!state.allowsTreeStructuralPseudoClasses()) {
                return input.newCustomError(SelectorParseErrorKind.invalid_state);
            }
            return .{
                .host = try parse_inner_compound_selector(Impl, parser, input, state),
            };
        } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "not")) {
            return parse_negation(Impl, parser, input, state);
        } else {
            //
        }

        if (parser.parseAnyPrefix(name)) |prefix| {
            return parse_is_or_where(Impl, parser, input, state, GenericComponent(Impl).convertHelper_any, .{prefix});
        }

        if (!state.allowsCustomFunctionalPseudoClasses()) {
            return input.newCustomError(SelectorParseErrorKind.invalid_state);
        }

        const result = try parser.parseNonTsFunctionalPseudoClass(Impl, name, input);
        return .{ .non_ts_pseudo_class = result };
    }

    pub fn parse_simple_pseudo_class(
        comptime Impl: type,
        parser: *SelectorParser,
        location: css.SourceLocation,
        name: []const u8,
        state: SelectorParsingState,
    ) Error!GenericComponent(Impl) {
        if (state.allowsNonFunctionalPseudoClasses()) {
            return location.newCustomError(SelectorParseErrorKind.invalid_state);
        }

        if (state.allowsTreeStructuralPseudoClasses()) {
            // css.todo_stuff.match_ignore_ascii_case
            if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "first-child")) {
                return .{ .nth = NthSelectorData.first(false) };
            } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "last-child")) {
                return .{ .nth = NthSelectorData.last(false) };
            } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "only-child")) {
                return .{ .nth = NthSelectorData.only(false) };
            } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "root")) {
                return .root;
            } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "empty")) {
                return .empty;
            } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "scope")) {
                return .scope;
            } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "host")) {
                return .{ .host = null };
            } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "first-of-type")) {
                return .{ .nth = NthSelectorData.first(true) };
            } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "last-of-type")) {
                return .{ .nth = NthSelectorData.last(true) };
            } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "only-of-type")) {
                return .{ .nth = NthSelectorData.only(true) };
            } else {}
        }

        // The view-transition pseudo elements accept the :only-child pseudo class.
        // https://w3c.github.io/csswg-drafts/css-view-transitions-1/#pseudo-root
        if (state.intersects(SelectorParsingState{ .after_view_transition = true })) {
            if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "only-child")) {
                return .{ .nth = NthSelectorData.only(false) };
            }
        }

        const pseudo_class = try parser.parseNonTsPseudoClass(location, name);
        if (state.intersects(SelectorParsingState{ .after_webkit_scrollbar = true })) {
            if (!pseudo_class.isValidAterWebkitScrollbar()) {
                return location.newCustomError(SelectorParseErrorKind{ .invalid_pseudo_class_after_webkit_scrollbar = true });
            }
        } else if (state.intersects(SelectorParsingState{ .after_pseudo_element = true })) {
            if (!pseudo_class.isUserActionState()) {
                return location.newCustomError(SelectorParseErrorKind{ .invalid_pseudo_class_after_pseudo_element = true });
            }
        } else if (!pseudo_class.isValidBeforeWebkitScrollbar()) {
            return location.newCustomError(SelectorParseErrorKind{ .invalid_pseudo_class_before_webkit_scrollbar = true });
        }

        return .{ .non_ts_pseudo_class = pseudo_class };
    }

    pub fn parse_nth_pseudo_class(
        comptime Impl: type,
        parser: *SelectorParser,
        input: *css.Parser,
        state: SelectorParsingState,
        ty: NthType,
    ) Error!GenericComponent(Impl) {
        if (!state.allowsTreeStructuralPseudoClasses()) {
            return input.newCustomError(SelectorParseErrorKind.invalid_state);
        }

        const a, const b = try css.nth.parse_nth(input);
        const nth_data = NthSelectorData{
            .ty = ty,
            .is_function = true,
            .a = a,
            .b = b,
        };

        if (!ty.allowsOfSelector()) {
            return .{ .nth = nth_data };
        }

        // Try to parse "of <selector-list>".
        input.tryParse(css.Parser.expectIdentMatching, .{"of"}) catch {
            return .{ .nth = nth_data };
        };

        // Whitespace between "of" and the selector list is optional
        // https://github.com/w3c/csswg-drafts/issues/8285
        var child_state = child_state: {
            var s = state;
            s.skip_default_namespace = true;
            s.disallow_pseudos = true;
            break :child_state s;
        };

        const selectors = try SelectorList.parseWithState(
            parser,
            input,
            &child_state,
            .ignore_invalid_selector,
            .none,
        );

        return .{
            .nth_of = NthOfSelectorData(Impl){
                .data = nth_data,
                .selectors = selectors.v.items,
            },
        };
    }

    /// `func` must be of the type: fn([]GenericSelector(Impl), ...@TypeOf(args_)) GenericComponent(Impl)
    pub fn parse_is_or_where(
        comptime Impl: type,
        parser: *SelectorParser,
        input: *css.Parser,
        state: *SelectorParsingState,
        comptime func: anytype,
        args_: anytype,
    ) Error!GenericComponent(Impl) {
        bun.debugAssert(parser.parseIsAndWhere());
        // https://drafts.csswg.org/selectors/#matches-pseudo:
        //
        //     Pseudo-elements cannot be represented by the matches-any
        //     pseudo-class; they are not valid within :is().
        //
        var child_state = brk: {
            var child_state = state.*;
            child_state.skip_default_namespace = true;
            child_state.disallow_pseudos = true;
            break :brk child_state;
        };

        const inner = try SelectorList.parseWithState(parser, input, &child_state, parser.isAndWhereRecovery(), NestingRequirement.none);
        if (child_state.after_nesting) {
            state.after_nesting = true;
        }

        const selector_slice = inner.v.items;

        const result = result: {
            const args = brk: {
                var args: std.meta.ArgsTuple(@TypeOf(func)) = undefined;
                args[0] = selector_slice;

                inline for (args_, 1..) |a, i| {
                    args[i] = a;
                }

                break :brk args;
            };

            break :result @call(.auto, func, args);
        };

        return result;
    }

    pub fn parse_has(
        comptime Impl: type,
        parser: *SelectorParser,
        input: *css.Parser,
        state: *SelectorParsingState,
    ) Error!GenericComponent(Impl) {
        var child_state = state.*;
        const inner = try SelectorList.parseRelativeWithState(
            parser,
            input,
            &child_state,
            parser.isAndWhereErrorRecovery(),
            .none,
        );

        if (child_state.after_nesting) {
            state.after_nesting = true;
        }
        return .{ .has = inner.v.items };
    }

    /// Level 3: Parse **one** simple_selector.  (Though we might insert a second
    /// implied "<defaultns>|*" type selector.)
    pub fn parse_negation(
        comptime Impl: type,
        parser: *SelectorParser,
        input: *css.Parser,
        state: *SelectorParsingState,
    ) Error!GenericComponent(Impl) {
        var child_state = state.*;
        child_state.skip_default_namespace = true;
        child_state.disallow_pseudos = true;

        const list = try SelectorList.parseWithState(parser, input, &child_state, .discard_list, .none);

        if (child_state.after_nesting) {
            state.after_nesting = true;
        }

        return .{ .negation = list.v.items };
    }

    pub fn OptionalQName(comptime Impl: type) type {
        return struct {
            some: struct { QNamePrefix(Impl), ?[]const u8 },
            none: css.Token,
        };
    }

    pub fn QNamePrefix(comptime Impl: type) type {
        return union(enum) {
            implicit_no_namespace, // `foo` in attr selectors
            implicit_any_namespace, // `foo` in type selectors, without a default ns
            implicit_default_namespace: Impl.SelectorImpl.NamespaceUrl, // `foo` in type selectors, with a default ns
            explicit_no_namespace, // `|foo`
            explicit_any_namespace, // `*|foo`
            explicit_namespace: struct { Impl.SelectorImpl.NamespacePrefix, Impl.SelectorImpl.NamespaceUrl }, // `prefix|foo`
        };
    }

    /// * `Err(())`: Invalid selector, abort
    /// * `Ok(None(token))`: Not a simple selector, could be something else. `input` was not consumed,
    ///                      but the token is still returned.
    /// * `Ok(Some(namespace, local_name))`: `None` for the local name means a `*` universal selector
    pub fn parse_qualified_name(
        comptime Impl: type,
        parser: *SelectorParser,
        input: *css.Parser,
        in_attr_selector: bool,
    ) Error!OptionalQName(Impl) {
        const start = input.state();

        const tok = input.nextIncludingWhitespace() catch |e| {
            input.reset(&start);
            return e;
        };
        switch (tok.*) {
            .ident => |value| {
                const after_ident = input.state();
                const n = if (input.nextIncludingWhitespace()) |t| t == .delim and t.delim == '|' else false;
                if (n) {
                    const prefix: Impl.SelectorImpl.NamespacePrefix = value;
                    const result: ?Impl.SelectorImpl.NamespaceUrl = parser.namespaceForPrefix(prefix);
                    const url: Impl.SelectorImpl.NamespaceUrl = try brk: {
                        if (result) break :brk result.*;
                        return input.newCustomError(SelectorParseErrorKind{ .unsupported_pseudo_class_or_element = value });
                    };
                    return parse_qualified_name_eplicit_namespace_helper(
                        Impl,
                        input,
                        .{ .explicit_namespace = .{ prefix, url } },
                        in_attr_selector,
                    );
                } else {
                    input.reset(&after_ident);
                    if (in_attr_selector) return .{ .some = .{ .implicit_no_namespace, value } };
                    return parse_qualified_name_default_namespace_helper(Impl, parser, value);
                }
            },
            .delim => |c| {
                switch (c) {
                    '*' => {
                        const after_star = input.state();
                        const result = input.nextIncludingWhitespace();
                        if (result) |t| if (t == .delim and t.delim == '|')
                            return parse_qualified_name_eplicit_namespace_helper(
                                Impl,
                                input,
                                .explicit_any_namespace,
                                in_attr_selector,
                            );
                        input.reset(after_star);
                        if (in_attr_selector) {
                            if (result) |t| {
                                return after_star.sourceLocation().newCustomError(SelectorParseErrorKind{
                                    .expected_bar_in_attr = t.*,
                                });
                            } else |e| {
                                return e;
                            }
                        } else {
                            return parse_qualified_name_default_namespace_helper(Impl, parser, null);
                        }
                    },
                    '|' => return parse_qualified_name_eplicit_namespace_helper(Impl, input, .explicit_no_namespace, in_attr_selector),
                    else => {},
                }
            },
            else => {},
        }
        input.reset(&start);
        return .{ .none = tok.* };
    }

    fn parse_qualified_name_default_namespace_helper(
        comptime Impl: type,
        parser: *SelectorParser,
        local_name: ?[]const u8,
    ) OptionalQName(Impl) {
        const namespace = if (parser.defaultNamespace()) |url| .{ .implicit_default_namespace = url } else .implicit_any_namespace;
        return .{
            .some = .{
                namespace,
                local_name,
            },
        };
    }

    fn parse_qualified_name_eplicit_namespace_helper(
        comptime Impl: type,
        input: *css.Parser,
        namespace: QNamePrefix(Impl),
        in_attr_selector: bool,
    ) Error!OptionalQName(Impl) {
        const location = input.currentSourceLocation();
        const t = input.nextIncludingWhitespace() catch |e| return e;
        switch (t) {
            .ident => |local_name| return .{ .some = .{ namespace, local_name } },
            .delim => |c| {
                if (c == '*') {
                    return .{ .some = .{ namespace, null } };
                }
            },
            else => {},
        }
        if (in_attr_selector) {
            const e = SelectorParseErrorKind{ .invalid_qual_name_in_attr = t.* };
            return location.newCustomError(e);
        }
        return location.newCustomError(SelectorParseErrorKind{ .explicit_namespace_expected_token = t.* });
    }

    pub fn LocalName(comptime Impl: type) type {
        return struct {
            name: Impl.SelectorImpl.LocalName,
            lower_name: Impl.SelectorImpl.LocalName,
        };
    }

    /// An attribute selector can have 's' or 'i' as flags, or no flags at all.
    pub const AttributeFlags = enum {
        // Matching should be case-sensitive ('s' flag).
        case_sensitive,
        // Matching should be case-insensitive ('i' flag).
        ascii_case_insensitive,
        // No flags.  Matching behavior depends on the name of the attribute.
        case_sensitivity_depends_on_name,

        pub fn toCaseSensitivity(this: AttributeFlags, local_name: []const u8, have_namespace: bool) attrs.ParsedCaseSensitivity {
            _ = local_name; // autofix
            _ = have_namespace; // autofix
            return switch (this) {
                .case_sensitive => .explicit_case_sensitive,
                .ascii_case_insensitive => .ascii_case_insensitive,
                .case_sensitivity_depends_on_name => {
                    @compileError(css.todo_stuff.depth);
                },
            };
        }
    };

    /// A [view transition part name](https://w3c.github.io/csswg-drafts/css-view-transitions-1/#typedef-pt-name-selector).
    pub const ViewTransitionPartName = union(enum) {
        /// *
        all,
        /// <custom-ident>
        name: css.css_values.ident.CustomIdent,
    };

    pub fn parse_attribute_flags(input: *css.Parser) Error!AttributeFlags {
        const location = input.currentSourceLocation();
        const token = input.next() catch {
            // Selectors spec says language-defined; HTML says it depends on the
            // exact attribute name.
            return AttributeFlags.case_sensitivity_depends_on_name;
        };

        const ident = if (token.* == .ident) token.ident else return location.newBasicUnexpectedTokenError(token.*);

        if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(ident, "i")) {
            return AttributeFlags.ascii_case_insensitive;
        } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(ident, "s")) {
            return AttributeFlags.case_sensitive;
        } else {
            return location.newBasicUnexpectedTokenError(token.*);
        }
    }
};