# Apple's HIG, read against Mindlore

Read on 2026-09-27: all 173 pages of the Human Interface Guidelines (pulled through the site's JSON API at `developer.apple.com/tutorials/data/design/human-interface-guidelines/*.json`), plus the Design landing page, Get Started, SF Symbols, and Icon Composer pages. The iOS and iPadOS 27 Figma kit is not in here yet. The five notes files in `hig-notes/` hold Apple's rules with the numbers intact; this page is what they mean for the app. Every claim below about Mindlore's code was checked against the tree on the date above.

Read the relevant notes file before designing a screen, not after. `hig-notes/1-visual-foundations.md` covers color, dark mode, Liquid Glass, type, layout, SF Symbols, app icons, motion. `2-behavior.md` covers generative AI, privacy, writing, haptics, loading, onboarding, undo, modality, settings, notifications, iCloud. `3-navigation.md` covers tab bars, toolbars, search, sheets, alerts, menus, lists, scroll views, progress. `4-input-and-system.md` covers text, pickers, gestures, charts, audio, sharing, widgets, Live Activities, App Shortcuts, controls, in-app purchase, reviews. `5-watch-mac-ipad.md` is the platform roadmap in order.

## The numbers worth knowing by heart

Hit targets are 44 by 44 points on iOS, 28 by 28 at the absolute minimum. Text contrast is 4.5:1 up to 17pt and 3:1 at 18pt or bold, in both light and dark; Apple suggests 7:1 for custom colors in small text. Every custom color needs an increased-contrast variant beside its light and dark ones. A screen has at most one prominent button. A segmented control has five segments or fewer on iPhone. An app gets up to four Home Screen quick actions and ten App Shortcuts. The review prompt is capped by the system at three times in 365 days. A Live Activity lasts up to eight hours and lingers up to four more on the Lock Screen unless the app ends it sooner. A watch session should finish inside a minute.

## Where Mindlore already agrees with Apple

The design system encodes the HIG's central rules rather than approximating them. `CardStyle.swift` says glass is for what floats over content, never for content, which is Apple's Liquid Glass rule nearly word for word. `Typography.swift` takes text styles only, never point sizes. `Motion.swift` gives each animation one meaning (settle, bloom, carry, breathe) and `Motion.resolve(_:reduceMotion:)` drops to opacity when Reduce Motion is on; `MindView` and `SearchPanel` read the setting too. Colors come only from the asset catalog, and `Palette.ember` is spent sparingly, which is Apple's advice for an accent.

Behavior lines up just as closely. Deleting through `UndoQueue` with no alert is what the Alerts page asks for ("avoid displaying alerts for common, undoable actions, even when they're destructive"), and `JournalWipe` keeping its confirmation is the exception Apple names: uncommon and permanent. The iCloud page's "warn before deleting" rule is about documents in file-based apps, not rows in a journal. Closing Settings before `AISettingsSheet` presents matches "display only one sheet at a time". `AIConsent` naming OpenAI and what it receives, behind an explicit Allow, is the generative AI page's permission rule, and Ask streaming its first sentence inside a second is the Loading page's "show something as soon as possible". `DailyReminder` (one a day, off by default, neutral words, no badge) passes every notification rule. `RecordAccessory` persisting over the tab bar is the pattern Apple uses for Music's mini player, and Reflect's three-way segmented control is the textbook use.

## Deliberate breaks from the HIG, kept on purpose

The + over the tab bar is the one real departure. Apple says a tab bar is for navigation, and an action in the tab row is what it warns against. Mindlore draws the + over the middle slot and keeps a real tab under it for VoiceOver, so the bar still reads as navigation to assistive tech; the owner chose this on 2026-09-24. If it is ever revisited, iOS 26's own answer is a toolbar or a floating glass button, not a tab.

The per-app appearance switch (`AppearancePreference`) goes against "avoid an app-specific appearance setting". It exists because `.preferredColorScheme` left sheets in the old scheme. Dynamic Type and accessibility-size layout passes are skipped by the owner's choice, where the HIG says to test at the largest sizes.

## Gaps, confirmed in the code

None of the 22 color sets in `Assets.xcassets` has an increased-contrast variant, so Increase Contrast does nothing for the palette, area, kind, or mood colors. This is the only gap here that the HIG states as a requirement.

The app icon is three PNGs (`AppIcon.png`, `-dark`, `-tinted`). iOS 26 icons are layered and built in Icon Composer, which renders the clear and tinted appearances and the glass's specular edge from the layers; a flat PNG gets none of that. This belongs in the launch work, since the icon is the first thing an App Store visitor sees.

Color carries meaning alone in places: mood colors on Reflect's charts and the area colors are the ones to check for a shape, symbol, or label backing each hue. Kind colors on Mind already have a second channel in the badge text and the tag pin's size.

Nothing asks for a review (`RequestReviewAction` appears nowhere). For a launch this is the cheapest item on the list: ask after a moment of demonstrated value, such as a first Life reading or a tenth entry, never during onboarding, and let the system's cap do the throttling.

Today's card row shows "2 of 9" under a paging scroll. Apple warns against showing a page indicator and a scroll indicator on the same axis; check the row hides its horizontal scroll indicator.

## Opportunities the HIG points straight at

Each of these reuses the App Intents Mindlore already has (Start Recording, New Written Entry, Ask Your Journal).

A Control Center control and Action button binding for Start Recording is a few dozen lines around an existing intent, and it cuts capture to one press from anywhere. It should be a button control, not a toggle. Home Screen quick actions (New Entry, Record, Ask, and one free slot) cost about the same.

A Live Activity for a recording in progress is the clearest fit on the whole list: bounded, time-based, one control. It shows "Recording" and the elapsed time, never words, since journal content is exactly what the HIG says to keep off the Lock Screen, and it ends the moment `stop()` runs rather than lingering.

Widgets are a larger piece. The honest candidates are the loose end Today would open on, deep-linking to it, and an interactive widget with a Record button. Nothing with a streak: About already refuses streaks, and a widget should too. (The watch notes suggest a streak complication; that contradicts the app and is not a recommendation.)

In-app purchase does not apply: the owner chose on 2026-09-27 to ship Mindlore free, with no purchase. If that ever changes, the rules are in `hig-notes/4-input-and-system.md`.

## The platform roadmap, per the HIG

The watch should do one thing: start a recording in under a minute, from a complication or the Action button, and show counts or status, never entry text, because Always On puts the face in view of anyone nearby. The Digital Crown is the primary navigation input. Recording on the wrist needs its own audio session work, not a port of `AudioRecorder`.

The Mac should be native, not Catalyst. The tabs become a `NavigationSplitView` sidebar, the fan becomes a toolbar button and File menu items, and the insights sheet becomes a trailing inspector. The menu bar has a fixed shape (App, File, Edit, Format, View, Window, Help) with standard item names, and the editor's formatting maps onto the Format menu with the usual shortcuts.

The iPad has to work in full screen and in freely resizable windows, with no signal telling the app which it is in. The tab bar moves to the `sidebarAdaptable` style. For handwritten entries, ink starts the instant the Pencil touches down with no mode switch, PencilKit is the foundation rather than a custom renderer, and Scribble works for free in stock text views but `GrowingTextEditor` is custom and will need `UIIndirectScribbleInteraction` wiring. Double-tap, squeeze, and barrel roll must never do anything destructive.

## What the HIG says about AI, which is most of this app

The generative AI page reads like a review of Mindlore's AI layer, and most of it passes: explicit consent, minimal data (`AskSources` as the single gate), an on-device option, reversible output (`originalText` and revert for cleanups), and no destructive action taken on the user's behalf. Two points go further than the app does today. Apple asks for specific progress wording during generation ("Finding substitutions for ingredients", not "Processing"), which is worth a pass over the insights and title states. And it asks for a simple, voluntary way to say an answer was wrong; Life's "That's right" and "Not quite" do this for the portrait, and nothing does it for Ask or insights yet.
