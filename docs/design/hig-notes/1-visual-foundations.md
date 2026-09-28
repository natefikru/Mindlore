# HIG notes: visual foundations (color, dark mode, materials, typography, layout, icons, motion, branding)

Group covers: color, dark-mode, materials, typography, layout, icons, sf-symbols, images, app-icons, motion, branding, designing-for-ios, design-principles, getting-started, foundations, color-wells.

## Design principles (foundations for everything else)

Eight principles Apple names explicitly: Purpose (make something meaningful, identify what matters most), Agency (let people do things their own way, make it easy to recover from mistakes), Responsibility (be transparent about data use), Familiarity (build on what people know, keep visuals and interactions consistent), Flexibility (adapt to diverse contexts, design for everyone, accessibility from the start), Simplicity (not minimalism, every element earns its place), Craft (care about every detail, iterate, maintain quality after shipping), Delight (make it human, not decoration).

Two lines worth keeping literally: "Simplicity isn't minimalism. Aim for a focused, useful experience that keeps the important things close by and lets the others fall away." And on delight: "Don't mistake delight for decoration... don't let pursuit of delight for its own sake get in the way of your product's core purpose."

For Mindlore: the app's own writing style (dense, specific CLAUDE.md prose; no filler) already tracks "Craft" and "Simplicity." The design system files (`Palette.swift`, `Motion.swift`, `ChipStyle.swift`) all carry comments explaining *why* a choice was made and citing an owner/date, which is itself a "Craft" artifact worth preserving as the app grows.

## Color

System provides semantic dynamic colors (label/secondaryLabel/tertiaryLabel/quaternaryLabel, separator/opaqueSeparator, link, systemBackground vs systemGroupedBackground with primary/secondary/tertiary variants) that adapt to light/dark and increased contrast automatically. Rule: never hard-code system color values; never redefine a semantic color's meaning (don't use separator color as a text color).

Custom colors: must supply light AND dark variants, and an increased-contrast variant for each, even if the app ships in one appearance only ("to support Liquid Glass adaptivity"). Color profile: sRGB is safe everywhere; Display P3 (wide color) gives richer saturation on compatible displays, use 16 bpc PNG when doing so; supply per-color-space variants in the asset catalog when P3 and sRGB colors look meaningfully different.

Liquid Glass color: by default Liquid Glass has no inherent color, it takes color from content behind it. Color can be applied to *some* Liquid Glass elements (staining) for emphasis, e.g. system uses the app accent color on a prominent Done button background, not on its label. Rule: apply color sparingly, and prefer applying color to backgrounds (not symbols/text) to signal emphasis. Small elements (toolbars, tab bars) default to a monochrome scheme that darkens/lightens with content; large elements (sidebars) go more opaque to preserve legibility. Avoid coloring the background of multiple controls at once, reserve it for the one primary action or status indicator.

Inclusive color: never rely on color alone to convey information (add text/shape too); check color-blind legibility; be aware of cultural color connotations.

Best practice: same color must mean the same thing everywhere in the UI (don't reuse the brand/accent color for both an interactive borderless button and static styled text).

Contrast: called out explicitly in Dark Mode doc (color doc itself has no number), minimum 4.5:1 for system-defined colors, and *strive for 7:1* with custom foreground/background pairs, especially small text.

For Mindlore:
- `Palette.swift` already does this correctly: every named color (`paper`, `card`, `ink`, area colors, entity-kind colors, mood colors) is a `Color(.assetName)` backed by an asset-catalog color set, which is exactly the "supply light and dark variants, never hard-code" rule. Comment even states "so nothing here names a number."
- Color is used consistently per-semantic-purpose throughout the codebase (CLAUDE.md: entity kind = one hue per kind on Mind's map, mood dots "never good or bad," area colors used only for area chips), matches "avoid using the same color to mean different things."
- One thing not verified in code: whether the increased-contrast variants exist for the custom asset colors (Palette, area, kind, mood sets). Worth an audit pass against the asset catalog when this work starts, since HIG requires an increased-contrast variant per light/dark pair even for custom colors.

## Dark Mode

Systemwide setting; app-specific appearance toggles are discouraged (Mindlore does have `AppearancePreference` with system/light/dark, this is an explicit exception pattern Apple tolerates but calls "avoid" by default; worth noting as a deliberate divergence, not an oversight, given the app's serif/paper aesthetic is a strong part of its identity).

Dark Mode palette isn't a strict inversion of light, some colors invert, some don't. iOS uses "base" and "elevated" background colors in dark mode to convey depth between layered surfaces (sheets/popovers get elevated background automatically), using a custom background color here breaks that system-provided depth cue.

Contrast minimum again stated here: 4.5:1 general, 7:1 target for custom colors especially in small text. Turning on Increase Contrast + Reduce Transparency together in Dark Mode can expose text/background pairs that go illegible, must test that combination specifically.

Icons/images: use SF Symbols (auto-adapt); for custom full-color icons, only create separate light/dark assets if the single asset doesn't read well in both.

For Mindlore:
- `AppearancePreference.swift` deliberately offers a per-app appearance override (system/light/dark), applied via `UIUserInterfaceStyle` on the window rather than `.preferredColorScheme`, specifically because the modifier-based approach left sheets stuck in the old scheme. This is a considered exception to the "avoid app-specific appearance setting" guidance, flag it as a known, justified divergence rather than something to "fix."
- `Palette.paper`/`Palette.card` are named for elevation-like roles (paper = base, card = elevated content surface) but are custom, not the system's own elevated/base colors, this is fine as long as light/dark/increased-contrast variants exist for both, matching the "prefer system background colors, but if you go custom supply the equivalent depth cues" spirit.

## Materials (Liquid Glass vs standard materials)

Liquid Glass: a distinct floating functional layer for controls/navigation (tab bars, sidebars) that sits above the content layer; content should scroll/peek through it. Hard rule: **don't use Liquid Glass in the content layer**, only standard materials belong there, with one exception: a transient interactive control (Slider, Toggle) can adopt a Liquid Glass look at the moment of activation. Use Liquid Glass sparingly on custom controls; standard system components pick it up automatically.

Two Liquid Glass variants: regular (blurs + adjusts luminosity of background, used by most system components, prefer when background is legibility-risky or content-heavy e.g. alerts/sidebars/popovers) and clear (highly translucent, for floating over rich media backgrounds like photo/video). Clear variant needs a dimming layer: add 35% opacity dark dimming layer if background is bright; skip it if background is already dark or if using AVKit's own dimming.

Standard materials (iOS/iPadOS): ultraThin, thin, regular (default), thick, pick by contrast need, not by apparent tint (system settings can change how a material looks). Use vibrant colors on top of materials (never plain colors), vibrancy tiers: label/secondaryLabel/tertiaryLabel/quaternaryLabel (avoid quaternary on thin/ultraThin, contrast too low), fill/secondaryFill/tertiaryFill, one separator tier.

For Mindlore:
- `CardStyle.swift`'s explicit comment: "An opaque content card: Card colour, a hairline, no shadow. Glass is for what floats over content, never for content itself." This is a direct, correctly-internalized restatement of the "don't use Liquid Glass in the content layer" rule, a good sign the design system already encodes this principle rather than needing retrofitting.
- CLAUDE.md documents multiple places where Liquid Glass is deliberately used for floating chrome only: Mind's top bar (`GlassEffectContainer`), Ask's input field ("Liquid Glass over solid Paper"), Settings sheets, consistent with HIG. Worth double-checking the "regular vs clear" variant choice matches use case (Ask's field floats over Paper, not media, so regular seems right; no dimming layer needed).

## Typography

Default/minimum legible sizes per platform: iOS/iPadOS default 17pt, minimum 11pt. Avoid light font weights (Ultralight/Thin/Light) especially at small sizes; prefer Regular/Medium/Semibold/Bold.

Two system typeface families: San Francisco (SF Pro is the iOS/iPadOS system font; SF Compact for watchOS; rounded variants available) and New York (NY, a serif, "designed to work well by itself and alongside SF"). Both ship as variable fonts supporting continuous optical sizing, don't need discrete size buckets in a design tool that supports variable fonts.

Text styles (the API surface: largeTitle, title1/2/3, headline, body, callout, subhead, footnote, caption1/2) bundle weight+size+leading per Dynamic Type size and scale together automatically, strongly prefer these over hardcoded font sizes; they are the mechanism by which Dynamic Type and accessibility text sizes work at all. Symbolic traits (e.g. `.bold()`) can add emphasis to a text style without breaking its Dynamic Type scaling.

Dynamic Type: must support it; layout must adapt at largest sizes (stack horizontally-adjacent views vertically if needed at accessibility sizes; grow list rows rather than truncate/clip); prioritize which content actually needs to scale (tab titles, hit-point numbers, etc., don't need to track body text size); keep truncation to a minimum, avoid truncating text in scrollable regions.

Full point-size table given for iOS/iPadOS across all 7 standard Dynamic Type sizes (xSmall through xxxLarge) and 5 accessibility sizes (AX1-AX5), each showing weight/size/leading/emphasized-weight per text style. Representative default (Large) sizes: Large Title 34/41, Title1 28/34, Title2 22/28, Title3 20/25 (semibold emphasized), Headline 17/22 (semibold), Body 17/22, Callout 16/21, Subhead 15/20, Footnote 13/18, Caption1 12/16, Caption2 11/13. At AX5 (largest), Body grows to 53pt/62pt leading, a 3x jump apps must survive without breaking layout.

Custom fonts: must implement Dynamic Type and Bold Text accessibility behavior themselves (system fonts get this for free); follow the same minimum-size guidance.

For Mindlore:
- The app already follows the "text styles, never point sizes" rule precisely: `Typography.swift`'s comment states "Text styles only, never point sizes, so Dynamic Type keeps working," and `.journalText(_:weight:)` takes a `Font.TextStyle`, not a raw size. This is a clean, correct implementation of the HIG's central typography rule.
- Mindlore inverts the "SF everywhere" default by design: user's own words render in `JournalFont` (serif/sans/rounded/monospaced, all still **system designs** via `Font.Design`/`UIFontDescriptor.SystemDesign`, never bundled custom fonts) while app chrome stays SF, this satisfies HIG's "use text styles with system fonts to keep Dynamic Type support" even while expressing a deliberate serif-by-default identity (New York is explicitly Apple's own recommended serif pairing with SF, so this is squarely inside HIG's blessed pattern, not a custom-font risk).
- Worth checking at accessibility sizes (AX1-AX5): CLAUDE.md's own "no accessibility checks" project note says Dynamic Type/AX-size screenshot passes are explicitly skipped by owner request, flag this as a known, chosen gap versus HIG's "must test layouts at largest accessibility sizes," not a discovery to act on unprompted.

## Layout

Visual hierarchy: order by importance top-to-bottom, leading-to-trailing (reading order); align elements to aid scanning; use indentation to signal subordination; group related items via spacing/containers/separators; use progressive disclosure (disclosure triangles, nested views, scrollable sections) rather than showing everything at once; differentiate controls from content using Liquid Glass + scroll edge effects rather than solid/semi-opaque backgrounds under controls.

Adaptability: apps must handle regular/compact horizontal and vertical size classes, device rotation, external displays, resizable windows, Dynamic Type changes, and locale/RTL. Size classes (not device type or orientation) should drive layout decisions, an app can appear in any combination of size classes via multitasking/mirroring. Keep functionality constant across size classes; only the amount of visible-at-once functionality should change (e.g., switching tab bar to sidebar when space allows).

Guides and safe areas: respect system layout guides (for margins, readable text width) and safe areas (avoid hardware features like Dynamic Island, avoid toolbars/tab bars covering content).

No iOS-specific extra considerations noted (layout doc says "No additional considerations for iOS or iPadOS" beyond the general guidance above); the macOS/tvOS/visionOS/watchOS-specific grid and spacing numbers (e.g. tvOS's 60pt/80pt safe-area insets, N-column grids) aren't relevant to Mindlore.

For Mindlore:
- The Journal → Mind → + → Reflect → Chat tab structure and RootView's `AppRouter` size-class-agnostic tab model likely already satisfies "keep functionality the same as size classes change" since iPhone-only in v1 avoids the multi-size-class matrix; revisit if/when iPad support is added per the platform roadmap.
- The "differentiate controls from content with Liquid Glass + scroll edge effect rather than solid backgrounds" rule maps directly onto documented choices: Ask's field ("Liquid Glass over solid Paper with a short fade above... on the whole bottom stack so the fade never lands on the search panel's last row"), Mind's top bar and drawer glass usage, these already use scroll-edge-effect-style fades rather than opaque bars.
- `UnclippedListRow.swift` exists specifically to let a horizontal strip (area chips) bleed to the screen edge inside a grouped list row, a custom workaround for a layout goal (edge-to-edge visual grouping) HIG doesn't call out directly but is consistent with "align elements... use negative space to show grouping."

## Icons (interface icons / glyphs) and SF Symbols

Interface icons ("glyphs," distinct from app icons) should be simple, instantly recognizable, using black/clear shapes the system tints. Must be visually consistent within an app: same size, level of detail, stroke weight, perspective across all icons, whether custom or SF Symbols mixed in. Match icon weight to adjacent text weight unless deliberately differentiating. Use vector formats (PDF/SVG) for custom icons, or SF Symbols with a custom scale, so they never need per-resolution raster assets. Provide accessibility labels for custom icons (VoiceOver). Don't design selected-state variants for standard components (system does this automatically). Avoid depicting Apple hardware.

SF Symbols specifics: nine weights (ultralight-black) matching SF font weights for precise text/symbol weight-matching; three scales (small/medium/large, medium default) tied to SF's cap height, letting a symbol's emphasis be tuned relative to adjacent text without breaking weight-matching. Four rendering modes: monochrome (one color, all layers), hierarchical (one color, per-layer opacity tiers = depth), palette (2+ explicit colors, one per layer), multicolor (intrinsic per-symbol colors like green `leaf`, red `trash.slash`, carries built-in meaning, use judiciously). Always prefer system-provided colors so a symbol auto-adapts to vibrancy/dark mode/accessibility.

Variable color: communicates a value changing over time (e.g. speaker volume level) by lighting up different layers at thresholds, explicitly "use variable color to communicate change, don't use it to communicate depth" (that's hierarchical's job).

Design variants: outline (default, text-like, best for toolbars/lists next to text), fill (more visual weight, good for tab bars/swipe actions/selection via accent color), plus slash and enclosed (circle/square) variants that combine with outline/fill. System views often pick outline vs fill automatically by context (tab bar prefers fill, toolbar prefers outline) so you often don't need to specify.

Animations (nine types): Appear/Disappear, Bounce (feedback that an action happened), Scale (persistent, e.g. selection emphasis), Pulse (opacity cycling, ongoing activity), Variable color (progress/ongoing activity, cumulative or iterative, open-loop vs closed-loop shapes), Replace (down-up/up-up/off-up state transitions) and Magic Replace (smart transition between related shapes, new default), Wiggle (draw attention to overlooked action), Breathe (opacity+size, living/ongoing quality, similar to but more than Pulse), Rotate (in-progress/spinning), Draw On/Draw Off (SF Symbols 7+, handwriting-like path reveal). Apply judiciously, too many animations overwhelm.

For Mindlore:
- No SF Symbols usage inventoried directly in `Design/` (icons are used inline per-view, not centralized), so a consistency pass, same weight/scale across all toolbar and tab icons, would be a reasonable HIG-driven audit item later; the icons doc's "maintain visual consistency across all interface icons" is the rule to check against.
- `Motion.breathe` (`Animation.easeInOut(duration: 2.4).repeatForever`) used for "the idle mic, AI at work" is a direct, deliberate parallel to SF Symbols' own Breathe animation semantics ("ongoing activity... a living quality"), the app's own custom motion vocabulary already mirrors Apple's symbol-animation taxonomy for the same use case, which is a good sign of internal consistency even though it's a custom `Animation`, not an actual `SymbolEffect`.
- Kind colors (`EntityKind.color`) using six well-separated hues plus a muted "dusty mauve" tag pin match SF Symbols' "use system-provided colors... hierarchical for depth, don't overload with too much palette-mode color" spirit in principle, though Mindlore's kind-coloring is custom UI (Mind's map), not SF Symbol rendering-mode usage per se.

## Images

Point vs pixel: a point is a resolution-independent unit; scale factors @1x/@2x/@3x determine raster density. iOS needs @2x and @3x assets for all bitmap images (iPadOS/watchOS only need @2x; macOS/tvOS need @1x/@2x). Design at lowest resolution and scale up; align vector control points to whole values at 1x so they stay crisp at 2x/3x multiples.

Format guidance table: bitmap/raster → de-interlaced PNG; PNG not needing 24-bit → 8-bit palette; photos → JPEG or HEIC; flat icons/interface icons/scalable flat art → PDF or SVG (never raster, for exactly the reason interface icons doc gives: PDF/SVG auto-scale, PNG needs multiple exports).

Always embed a color profile per image (sRGB safe everywhere; wide-gamut P3 for richer color on compatible displays, see Color doc). Always test images on real devices, design-time appearance can differ (pixelation, stretching, compression).

For Mindlore: this doc is aimed mainly at bitmap/photo assets and platform-specific parallax/spatial-photo handling (tvOS/visionOS), which the app doesn't use (iOS journaling app, photo entries are user-photographed pages, not app-supplied artwork). The one directly relevant rule: any custom raster art the app does ship (app icon aside) should be PDF/SVG if it's flat iconography, PNG/HEIC if photographic, nothing in `Design/` currently ships custom bitmap assets besides the color/asset catalog entries, so this is largely satisfied by construction.

## App icons

Layered design: iOS/iPadOS/macOS/watchOS icons use a background layer plus one or more foreground layers, composited through **Icon Composer** (a standalone tool bundled with Xcode) which applies Liquid Glass attributes (specular highlights, refraction, translucency) automatically and adapts them across icon sizes and system versions, you do not draw these effects yourself. Icon Composer also handles default/dark/mono appearance-variant annotation from one file, plus preview and export.

Shape: iOS/iPadOS/macOS = square canvas, masked to rounded rectangle matching device bezel curvature; visionOS/watchOS = square canvas, masked to circle; tvOS = rectangular, masked to rounded rectangle. Always supply **unmasked square (or rectangular) layers**, pre-masked/pre-rounded layers break the system's specular highlight and edge rendering. Keep primary content centered to survive corner-masking, especially for circular masks (visionOS/watchOS) where more gets clipped at the edges.

Design rules: embrace simplicity, one core concept in a minimal number of shapes; solid background (color or simple gradient) rather than filling the whole canvas with detail; consider overlapping filled shapes with transparency/blur for a sense of depth; avoid text unless essential (no localization/accessibility support, often illegible small, redundant with the nearby app name, a single mnemonic initial letter is acceptable, generic words like "Watch"/"New" are not); prefer illustration over photography (photos don't survive layering/small sizes/appearance variants well); never replicate system UI components or use screenshots; never reproduce Apple hardware.

Visual effects: let the system apply blur/highlights/shadow, don't bake in your own specular/bevel/glow effects, they're static where the system's are dynamic and will visually conflict.

Appearance variants: default, dark, clear (light/dark), tinted (light/dark), six total for iOS/iPadOS/macOS. Keep the same core visual features across all variants (don't swap elements in/out per variant, which confuses recognition when a person changes appearance). Base dark/tinted/clear icons on the light default, using complementary/more subdued colors, the system auto-generates variants you don't explicitly design, but explicit design is preferred for recognizability. Alternate app icons (a settings-level user choice, e.g. per-team icon) each need their own dark/clear/tinted set and are all subject to App Review.

Specifications: iOS/iPadOS/macOS layout size 1024x1024px, layered, six appearance variants. Formats: sRGB, Gray Gamma 2.2, Display P3.

For Mindlore: no app-icon source files were found in `Mindlore/Design/` during this pass (Design/ holds only in-app color/type/motion/chip primitives, not the actual icon artwork, which would live in an .icon/Icon Composer project or an asset catalog appiconset). This is a gap to note for whoever does the actual app-icon work: Mindlore should be authored in Icon Composer (not a flat PNG export) to get Liquid Glass specular/refraction treatment automatically and to support the six iOS appearance variants (default/dark/clear light/clear dark/tinted light/tinted dark) plus a "mono" annotation Icon Composer also handles. Given the "ember +" motif and warm paper/ink palette described in CLAUDE.md (Views section, `NewEntryFan`'s "ember +"), an icon built around a simple ember/flame or open-book mark on a warm solid-color background would fit both the "simple, one concept" rule and the existing brand palette.

## Motion

Core rule: motion must be purposeful, never decorative for its own sake; must never be the *only* channel carrying important information (pair with haptics/audio too); must be interruptible, don't force people to wait through an animation more than once. Feedback animations should be brief, precise, and match real gestures/expectations (a view dismissed the same way it was revealed). Avoid adding motion to very frequent interactions beyond what system components already provide.

SF Symbols animations (Bounce/Scale/Pulse/Breathe/etc., see Icons/SF Symbols section above) are explicitly suggested as an easy way to add purposeful motion "where it makes sense."

visionOS-specific guidance (peripheral motion discomfort, oscillation near 0.2Hz, world-rotation avoidance) doesn't apply to Mindlore (iOS-only).

For Mindlore:
- `Motion.swift`'s four-animation vocabulary (settle/bloom/carry/breathe) is a strong, deliberate implementation of "motion should mean one thing consistently", each name maps to a specific *kind* of event (arrival, discovery/noticing, object identity continuity, ongoing wait) rather than being reused arbitrarily, which is exactly what HIG's "feedback motion should follow expectations" is getting at.
- `Motion.resolve(_:reduceMotion:)` and `BloomTransition`'s explicit Reduce Motion fallback (opacity-only, no scale) directly implements "make motion optional", this is already correct and complete for the accessibility half of the motion guidance.
- `BloomCurve` reverse-engineers the exact spring math of `Motion.bloom` to drive a `Canvas`-based animation (Mind's graph nodes, which have no view identity/transition system), this is a sophisticated but correct way to extend the "one consistent motion vocabulary" principle into a rendering context (Canvas) that Apple's own animation APIs don't reach, rather than inventing a second, inconsistent motion for the graph.

## Branding

Best practices: use a consistent brand voice/tone in all copy; apply the app's accent color judiciously, not broadly across every control, but reserved for primary actions/status indicators (unread badges, selected tab), with brand color better expressed by putting it in the *content layer* (where it scrolls beneath Liquid Glass controls and gets picked up dynamically) rather than painting it onto chrome. Custom fonts are fine for headlines if legible and accessibility-compliant, but system fonts are usually better for body/caption legibility at small sizes, a common pattern is custom font for headers, system font for body. Prefer familiar system components over reinventing them; if customizing a component's appearance, preserve its sizing/placement/behavior conventions. Branding should defer to content, don't spend screen space on brand elements that displace what people actually came for; resist repeating the logo throughout the app since people rarely need reminding which app they're in. Don't use a launch screen as a branding moment (it disappears too fast), an onboarding/welcome screen is the right place for that instead.

For Mindlore:
- The "apply accent color judiciously, move brand expression into the content layer" guidance directly matches Mindlore's own accent-color usage as documented: `Palette.ember` (the accent) is reserved for the journal-kind badge, the "ember +" new-entry button, and primary-action emphasis, not painted broadly across chrome, this is HIG-aligned as built.
- "Custom font for headlines, system font for body" doesn't map onto Mindlore's approach directly, since the split there is by *authorship* (user's words vs. app's chrome), not by *hierarchy level*, this is a different, deliberate axis, so it isn't in tension with HIG so much as orthogonal to it; worth noting only so future work doesn't try to force it into the "headline vs body" mold.
- No onboarding/welcome screen with branding is documented in CLAUDE.md's Views section; if one exists or gets added, HIG's "put brand personality there, not on the launch screen" is the relevant rule to apply.

## Designing for iOS (platform fundamentals)

iPhone-specific baseline: medium-size high-res display, one-or-two-handed grip, viewing distance under a foot or two, Multi-Touch/keyboard/voice input, frequent app-switching, and system features (widgets, Home Screen quick actions, Spotlight, Shortcuts, Activity views/share sheet) that a well-integrated app should hook into. Best practices: limit onscreen controls to keep focus on primary tasks, surface secondary actions with minimal interaction (progressive disclosure again); adapt to orientation/Dark Mode/Dynamic Type; place reachable controls in the middle/bottom of the screen (thumb-reachable) and support swipe-to-navigate-back and swipe actions in list rows; use platform capabilities (biometric auth, location, payments) instead of asking people to re-enter data, always with permission.

For Mindlore:
- Mindlore already integrates two of the named system features directly per CLAUDE.md: App Intents (Start Recording, New Written Entry, Ask Your Journal) with Siri phrases, and a local daily reminder notification, both are explicit "system features" HIG calls out as worth adopting.
- The tab bar's ember "+" sitting in the bottom-middle slot and swipe-to-delete-with-Undo on list rows both match "place reachable controls in the middle/bottom" and "support swipe actions in list rows" directly.
- No Widget or Spotlight integration is documented yet, plausible future HIG-aligned additions once v1 stabilizes (e.g., a Spotlight-searchable entry index, or a Home Screen widget showing the day's loose end or streak-free totals), consistent with "About" screen's stated no-streaks policy so a widget would need to avoid streak framing.
