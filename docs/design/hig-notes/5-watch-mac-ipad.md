# HIG notes: Watch, Mac, iPad+Pencil (for Mindlore's platform roadmap)

## WATCH

### Concrete rules

**Device model.** Small, high-resolution display, worn about a foot from the eyes, viewed with the opposite hand free to interact. The Always On display means people glance at the watch face constantly without raising it fully. Interactions are meant to run under a minute. People use an app's complications, notifications, and Siri shortcuts more than the app itself, the app is often the least-used surface of a watchOS experience.

**Navigation model (watchOS 10+).** The Digital Crown is the primary navigation input, not a secondary one. Lists, tab views, and variable-height pages are vertically oriented specifically so the crown can drive them. On the watch face, turning the crown moves through the Smart Stack; on the Home Screen, it moves through the app grid; inside an app, it switches between vertically paginated tabs and scrolls lists. The crown also has a non-navigation use: inspecting a value in place (the World Clock example: turning the crown advances displayed time without navigating anywhere). Every crown-driven interaction needs a touch equivalent as backup. Apps cannot respond to a crown press, that gesture is reserved by the system (reveals the Home Screen). Crown turns should drive visible feedback at a matching speed; don't lag or throttle updates below what a fast turn implies, or people will assume the crown does nothing in your app. Most models give haptic detents on turn; the default is fine, but turn it off (or switch to linear detents) if your row heights are uneven or your own animation doesn't match the tap rhythm.

**Depth of hierarchy.** Keep it shallow. watchOS is built for single-screen, glanceable interactions performed with one or two gestures (tap, swipe, drag). Deep navigation stacks fight the form factor.

**Complications** (the watch-face accessories). watchOS 9+ groups them into families (circular, corner, inline, rectangular) with system-recommended layouts; a watch face declares which family each of its slots accepts. WidgetKit is the preferred implementation now (ClockKit is legacy-only, for pre-watchOS 9 support).
- Content over branding: people keep a complication that shows genuinely live, relevant data: a static complication with nothing dynamic to say tends to get removed from the watch face. If you truly have nothing to show, fall back to an app-icon-style image so the complication still functions as a launcher.
- Support as many families as feasible, more families means eligibility for more watch faces.
- Multiple complications per family are worth having if your app has multiple deep-linkable "modes" (their example: a triathlon app with separate swim/bike/run complications, each deep-linking straight to that segment).
- Every complication should deep-link to the specific area of the app it represents, not all to the same top-level screen.
- Privacy: complications sit on the Always-On display, which can be seen by people other than the wearer. Don't put sensitive content in a complication's default (non-obscured) state.
- Data updates run on a timeline of dated entries; the system caps how many timeline entries you can push per day and how many it stores, so choose update times deliberately rather than trying to update continuously.
- Tinted mode: the system can desaturate a complication to grayscale plus one wearer-chosen accent color. Never rely on color alone to convey meaning (also true generally); supply an alternate tinted image if your full-color art doesn't read well desaturated.
- Line weights of 2pt or more (thin lines vanish at a glance, worse in motion).
- Rectangular-family complications can also surface as widgets in the Smart Stack (watchOS 10+); optimize with a background color/content that communicates status, and use relevance intents so the system surfaces it at the right moment (see also Widgets watchOS section below: default Smart Stack background is black, a colored background you supply, e.g. red/green for a stock's direction, is worth doing.).
- Concrete image sizes exist per family per case size (40/41/44/45/49mm), pull exact px/pt values from Apple's spec pages at implementation time; not worth hardcoding here since Mindlore's own complication would likely be a simple circular or corner glyph/count.

**Watch faces.** A watch face is the whole customizable home view (accent color, complications, styling) that people choose as their default view; some faces are shareable (a configured face, with your complications, colors, images pre-set, that a person can save into their Watch app, and the system will offer to install your app if they don't have it). Only worth building if you have multiple complications strong enough to be worth featuring together and a face concept that showcases them (e.g. Mindlore streak count + last-entry mood together). Not all faces are available on all hardware; if a shared face targets a newer-only face, offer a fallback configuration for older watches, and handle the "incompatible face" system error gracefully rather than showing a raw failure.

**Always On.** On the watch, dropping the wrist dims (not blanks) the display, and the frontmost app (or an app running a background session) keeps showing, dimmed. Rules: redact anything sensitive by default (bank balances, health data, a journal entry's text or title would qualify). Keep the "important" content legible while dimming everything secondary, reduce backgrounds/color fills/images, keep primary text sharp. Never change layout structurally when entering/exiting Always On, transition an interactive element to an "unavailable" look rather than removing it outright. Make only infrequent, subtle updates while dimmed (a sports score updates only on an actual score change, not on every play). Motion in progress should ease to a stop, not cut abruptly, when Always On engages.

**Multitasking / windows / sidebars / split views / menu bar / pointing devices.** All explicitly **not supported** on watchOS except split views, which the HIG treats specially: on watchOS a "split view" just means the system shows either a list view or a single detail view full-screen, never side-by-side. Practical guidance: auto-select the most relevant detail on launch (based on time, location, or recent activity) rather than making the wearer choose; if you have multiple detail "pages" for one selection, stack them as a vertical TabView so the crown scrolls between them, and the system will draw its own page indicator alongside the crown.

**Audio.** watchOS manages playback for you. A foreground/active app can play short clips; longer audio can keep playing after the wrist drops or the person switches apps, if implemented as background audio.

**Notifications on Watch.** iPhone notification permissions apply to the paired Watch app by default. People get extra per-notification controls by swiping left on an arrived notification (Mute 1 Hour, turn off Time Sensitive for this app). Nothing app-specific to build here beyond standard notification content design.

**Live Activities on Watch.** If you don't ship a watchOS app, tapping your Live Activity in the Smart Stack opens a plain full-screen view whose only action is "open on iPhone." Shipping a watchOS app lets the tap open it directly. A custom watchOS Live Activity layout can add real interactive controls (buttons, toggles), but that same custom layout is reused for CarPlay, where the system strips interactivity, so don't design a layout whose value collapses without buttons.

### For Mindlore

The roadmap's own framing is right: Watch first, "quick voice capture, maybe a complication," before Mac or iPad. Given the HIG:

**Do:**
- Build one function, well: start-a-recording, glanceable and completable in under a minute, launched straight into a ready-to-record state (mirrors the existing `RecordingSession.Status.ready` behavior already used for the fan/Siri paths), tap once to actually start capturing, per the "let people begin instantly" pattern that governs Pencil/marking instruments and matches the app's existing rule that nothing records on open unless asked.
- Use the Action button (a hardware element the group didn't formally cover here but is mentioned in the watchOS intro) or a Siri-driven "Start Recording" shortcut as an alternate entry, reusing the existing `MindloreShortcuts`/App Intents work already built for iPhone.
- One complication to start: something honest and dynamic, not a static logo. A same-day entry count or "last entry N hours ago" is a legitimate live data point; a streak count is another candidate. Make it deep-link straight into "start recording," not into a generic app-open.
- Respect Always On redaction: never show entry text, titles, or mood on the dimmed watch face or in a complication's default state, Mindlore is a journal, and "what did I write about" is exactly the kind of casual-observer-visible content the HIG calls out by name (bank balances, health data are its examples; personal journal content is squarely the same category).
- Keep the crown as the one navigation control if the watch app ever needs more than a single screen (e.g., a short list of "last 5 entries" as text-only glanceable rows), vertical list, crown-scrollable, with touch scroll working too.
- If a "recent entries" list ships, treat it as the watchOS "split view" pattern: auto-show the most relevant single item (today's entry or the in-progress recording) rather than making the wearer pick from a list on open.

**Don't:**
- Don't try to replicate multi-pane, sidebar, or windowed navigation, none of that exists on watchOS, and the platform intentionally punishes deep hierarchy.
- Don't build a custom watch face at v1; that's a later, "shareable marketing surface" feature that depends on having complications worth featuring together, which won't exist yet.
- Don't show transcribed text on the watch. On-device speech models don't run there (per the main CLAUDE.md's simulator note, the phone/iPhone silicon already strains on this) and more importantly, Always On's privacy rule argues against surfacing raw journal text on the wrist at all, a complication or glance should show counts/status, not content.
- Don't put interactive buttons in a Live Activity layout if Mindlore ever ships one for "recording in progress," unless you're fine with that same layout losing all interactivity when mirrored to CarPlay; a passive "recording... tap to open app" is safer for v1.
- Don't assume background audio recording indefinitely "just works" the way the iPhone's PCM `AudioRecorder` does, watchOS explicitly gates long-running audio through its own background-audio session APIs; recording on the wrist needs a fresh implementation, not a port.

---

## MAC

### Concrete rules

**Device model.** Large, high-resolution display(s), Mac can extend across attached monitors, and can even use an iPad as an additional display. People are seated, roughly 1-3 feet away. Input is keyboard + pointing device (mouse/trackpad) as the default combination, with game controllers and Siri also possible. Sessions run from a couple of minutes to hours of sustained concentration, with several apps open and switched between constantly, multitasking is the default state on Mac, not an edge case.

**Menu bar**, mandatory system feature. Menu order is fixed: **AppName, File, Edit, Format, View, [app-specific menus], Window, Help**, plus the system Apple menu (leading) and menu bar extras (trailing, not under app control).
- Always show every menu item your app supports, even when inactive in the current context, disable, don't hide, so people can learn what your app can do by scanning the menu bar.
- Reuse system-standard menu items and their keyboard shortcuts verbatim (Copy/Cut/Paste/Save/Print etc.), don't invent new shortcuts for standard actions.
- App menu content and order: About AppName, Settings…, [app-specific config items], Services, Hide/Hide Others/Show All, Quit AppName. "About" gets its own separated group at the top. Settings is for app-level prefs only; document-specific settings go in File.
- File menu: New Item (name it after what you create, e.g. "New Entry"), Open, Open Recent, Close/Close Tab/Close File, Save (autosave periodically so people rarely need to invoke this manually, directly consistent with Mindlore's existing `EntrySaver` autosave-off-but-noteChange/flush model, which would need a Save-menu wrapper), Duplicate (prefer this over "Save As"/"Export"/"Copy To" naming), Rename, Move To, Export As (only for foreign formats), Revert To, Page/Print Setup.
- Edit menu is standard (Undo/Redo naming should include the target, e.g. "Undo Typing," "Undo Delete Entry", matches Mindlore's existing `UndoQueue` delete-undo pattern) plus system-provided Find, Spelling, Substitutions, Transformations, Speech, Start Dictation, Emoji & Symbols.
- Format menu only if you support rich text formatting, Mindlore's formatting model (headings, lists, checklists, bold/italic) is exactly the case this menu exists for.
- View menu governs show/hide of tab bar, toolbar, sidebar, and full-screen toggle; item titles must reflect current state ("Show Toolbar" vs "Hide Toolbar").
- App-specific menus sit between View and Window, ordered most-general to least-general, mirroring your app's own content hierarchy.
- Window menu is required even for a single-window app (for Full Keyboard Access users to Minimize/Zoom); lists all open windows by name for quick switching.
- Help menu at the trailing end: "Send AppName Feedback to Apple," "AppName Help."
- Menu bar extras (the small icon area top-right) are opt-in by the person, not forced on by the app; never assume yours will always be visible, since the system hides/reorders them under space pressure. Good use: a quick "record a voice note" trigger without opening the app, but the person must choose to add it, typically via a settings toggle.

**Windows.**
- Two conceptual kinds: primary windows (full navigation + content) and auxiliary windows (one task, no nav, closable when done).
- Never build custom window chrome, use system-provided frames/controls; a hand-rolled titlebar reads as "broken," not "custom."
- Three window states with distinct system-drawn appearances: main (frontmost), key (the one actually accepting input, usually but not always the same as main; a floating panel like Colors can be key while another window is main), inactive (dimmed, no materials/vibrancy). If you build any custom window-like UI, you must reproduce these appearance transitions yourself or it'll look wrong when backgrounded.
- Never put critical info or the only path to an action in a bottom bar, people routinely position windows so the bottom edge is off-screen or covered.
- Open a new window only for a genuinely separate task/context (their example: Mail's Compose opens a new window so the draft and the reference email are both visible), don't make "open in new window" the default click behavior everywhere.
- Refer to windows as "windows" in UI text, never "scene" (an implementation term) or other synonyms.

**Split views (macOS specifics).** Panes can be arranged vertically, horizontally, or both, separated by draggable dividers. Prefer the thin (1pt) divider unless both sides have strong linear content that would make a thin divider hard to see. Set sane min/max pane sizes so a divider never effectively disappears. Let people hide a pane for focus (e.g., hide navigator/notes to concentrate on editing) with more than one way to bring it back (toolbar button + View-menu command + shortcut).

**Sidebars (macOS specifics).** Row/text/glyph size scales with a size the person can pick (small/medium/large) in General settings, respect that setting, don't hardcode row height. Consider auto-collapsing the sidebar when the window gets small. Never put critical actions at the sidebar's bottom edge (same off-screen risk as window bottom bars). Sidebar icons should follow the system/app accent color by default so they follow a person's chosen accent; use a fixed color only to intentionally mark something as different (their example: Mail's yellow VIP icon).

**Pointing devices (macOS).** A large standard vocabulary of trackpad/mouse gestures exists system-wide (primary click, secondary click for context menus, scroll, smart zoom, swipe between pages/full-screen apps, Mission Control, force click for Look Up/Quick Look, pinch/rotate, Notification Center swipe, App Exposé, Launchpad, Show Desktop), never redefine or hijack these systemwide gestures inside your app, even in a "creative" context. Provide a full set of Mac-standard cursor shapes (arrow, I-beam variants, resize handles, pointing hand for links, open/closed hand for drag-to-pan, crosshair for precise rect-select, drag-copy/drag-link/disappearing-item/operation-not-allowed for drag feedback) wherever those semantics apply in your own custom views.

### For Mindlore

Given the roadmap ("native Mac app" as the second platform, after Watch):

**Do:**
- Build a real macOS app (this is explicitly favored over Mac Catalyst per the roadmap's "native Mac" framing, and the HIG content below on Mac Catalyst explains why: only worth Catalyst-porting when the iPad app is closer to being Mac-shaped already, and Mindlore's tab-bar-plus-half-circle-fan-plus-sheets navigation is deliberately touch/iPhone-shaped, not sidebar-shaped).
- Recast the app's tab bar (Journal/Mind/+/Reflect/Chat) as a macOS sidebar. The HIG's split-view/sidebar guidance basically prescribes this: "if you use a tab bar on iPad, consider a split view with a sidebar on Mac" is stated directly for Catalyst apps and generalizes, a native Mac Mindlore should use `NavigationSplitView` with a sidebar listing Journal, Mind, Reflect, Chat, with a toolbar "+" (New Entry / Record / Pages) replacing the floating ember-fan, since the fan is a touch-target affordance that doesn't map to pointer/keyboard interaction.
- Build a full standard menu bar: File (New Entry, per "name Item after what you create"), Edit (leverage system Undo/Redo, wired to the existing `UndoQueue` and entry edits), Format (bold/italic/heading/list/checklist, directly maps onto the existing `FormattingStyle` model), View (Show/Hide Sidebar, Show/Hide Loose Ends etc.), Window, Help.
- Autosave via the menu is basically free: File > Save can just call `EntrySaver.flush()`; don't require it, since journal entries already autosave, but include the menu item because Full Keyboard Access and habit expect it.
- Give the entity/insights panels an inspector-style presentation on the trailing edge of a split view (explicitly recommended pattern: "present inspector UI next to main content instead of a popover" for large screens) rather than the iPhone's modal insights sheet.
- Support standard trackpad/mouse gestures for the journal list and Mind's canvas: scroll, pinch-zoom on the graph view, secondary-click for context menus (rename entity, delete entry) mapping to iOS's existing long-press context menus.
- Multi-window is worth supporting for at minimum "open an entry in its own window" (Mail's Compose pattern) since journaling and reading naturally split into "write here, reference there."

**Don't:**
- Don't try to preserve the iPhone's floating "+" ember button or the half-circle fan chooser as-is; it's a touch gesture pattern with no pointer equivalent listed anywhere in this guidance, and pointing-device users expect discrete buttons/menu items instead.
- Don't put "Record"/"New Entry"/"New Pages" only in a menu-bar-hidden location, since the Mac menu bar is visible by default (unlike iPad's hidden-until-swiped bar), that's actually the right place for these, but back them up with toolbar buttons too, since people expect the toolbar to carry primary actions.
- Don't invent custom window chrome for any Mindlore window (e.g. a custom-styled entry-editor window), reuse system window frames throughout.
- Don't rely on a menu bar extra as Mindlore's only quick-capture path on Mac, the HIG is explicit that a person may never install one, and the app can't assume it's present; treat a "record from menu bar" icon as a nice add-on behind a settings opt-in, not the primary flow (a Dock menu, always available while running, is the more dependable equivalent).

---

## iPAD (WITH PENCIL)

### Concrete rules

**Device model.** Large, high-res display; held (not just set down) most of the time, viewing distance ~3 feet. Input modes: Multi-Touch, virtual keyboard, physical keyboard, pointing device (trackpad/mouse), Apple Pencil, voice, frequently combined. Sessions range from quick actions to hours of focused content creation. People routinely run multiple apps at once and expect drag-and-drop between them.

**Multitasking / windows (iPadOS specifics).** Two system-level modes a person chooses in Settings, apps don't control which: Full Screen (switch between app/window instances via the app switcher) or Windowed (freely resizable, repositionable, system remembers size/placement across launches, tiling controls provided by the system, frontmost window gets colored controls + drop shadow). Apps must adapt gracefully to arbitrary window sizes since they get no signal about which mode is active. Picture-in-Picture for video/FaceTime floats above either mode. In Windowed mode, watch out for window controls overlapping leading-edge toolbar buttons, inset your own leading toolbar items rather than letting the system controls cover them.

**Split views / sidebars (iPadOS specifics).** Two or three vertical panes (Mail-style two-pane, Keynote-style three-pane). Must handle narrow, compact, and intermediate widths gracefully since iPad windows are fluidly resizable, plan navigation logic for all of them, not just full-width. Sidebars: generally no more than two levels of hierarchy in a sidebar before you should switch to a full split view with an intermediate content list. The `sidebarAdaptable` tab-view style lets the same interface flip between a bottom tab bar and a leading sidebar depending on width, with a built-in switch button, worth knowing about, but the HIG's own advice is to default to a tab bar and treat the sidebar-convertible mode as the overflow case for apps with more sections than a tab bar comfortably holds.

**Pointing devices / trackpad (iPadOS specifics).** The pointer adapts contextually: circular by default, I-beam over text, custom shapes elsewhere. Content effects: highlight (translucent rounded-rect background, used on bar buttons/tab bars/segmented controls by default), lift (parallax + shadow + scale, used on app icons and Control Center buttons by default), hover (generic scale/tint/shadow you define yourself for larger custom elements). Rule of thumb for choosing: highlight for a small element with transparent background, lift for a small element with opaque background, hover for larger elements. Add roughly 12pt padding around bezeled elements and ~24pt around unbezeled ones for comfortable hit regions. Support click-drag band-selection in custom collection-style views if you want multi-select via pointer (standard non-list collection views get it for free). Never show instructional text attached to a pointer, and never make the pointer's only job be decorative.

**Apple Pencil and Scribble.** This is the section most relevant to the roadmap's eventual "handwritten entries" goal.
- Mark the instant Pencil touches the screen, no mode switch, no button tap required first, mirroring how a real pencil behaves on paper. This is stated almost identically to the app's own principle for starting a voice recording ("start capture the moment intent is expressed"), so it's a natural philosophical fit for Mindlore.
- Let people switch fluidly between Pencil and finger; any control that responds to touch should also respond to Pencil, or it reads as broken/dead-battery.
- Use tilt (altitude), pressure (force), orientation (azimuth), and (Pencil Pro) barrel roll to modulate strokes, pressure mapping to a continuous property (opacity, thickness) is the natural, expected mapping.
- Give visual feedback that a mark is directly, immediately tied to what Pencil touches; never let it look like it's acting at a distance.
- Design deliberately for both left- and right-handed use; if a control might get covered by either hand, let it be repositioned.
- Hover: use it to preview what a mark would look like (size/color) before it lands, but don't continuously vary the preview by height (jittery, unhelpful) and don't use hover to trigger an action outright, it's imprecise and shouldn't drive anything destructive or hard to undo. Prefer restricting hover-preview visuals to Pencil, not extending them to a trackpad pointer too (can read as inconsistent).
- Double-tap (on supporting Pencil models): respect the system-level double-tap setting (tool/eraser toggle, tool/previous-tool toggle, show/hide color picker, or off) if your app has an obvious mapping; never use double-tap for anything destructive or hard to undo, since accidental double-taps happen.
- Squeeze (Pencil Pro only): treat as a single discrete action, not continuous; show results near the Pencil tip if you invoke UI; must be nondestructive/undoable, same rationale as double-tap.
- Barrel roll (Pencil Pro only): only for modifying an in-progress mark (e.g., changing a highlighter's angle), never for navigation or summoning other UI.
- **Scribble**: on-device handwriting recognition that converts Pencil input to text in *any* standard text field automatically, no mode switch, this works for free in any standard `UITextField`/`UITextView`/SwiftUI TextField, but breaks if you've built a custom text component; a custom text field needs manual Scribble integration (`UIIndirectScribbleInteraction`) to keep it available. Practical writing-experience rules: no writing-obscuring autocomplete overlays while Scribble is active, hide placeholder text instantly on first stroke, keep the text field visually stationary while someone is actively writing (deferring any resize/reflow until they pause), prevent the view from autoscrolling out from under an in-progress selection, and give the field generous size up front, a cramped field feels bad to write in.
- **Custom drawing / PencilKit**: gives low-latency freehand drawing plus a built-in tool picker and ink palette essentially for free. Canvas colors auto-adjust for Dark Mode by default, good for a blank note, wrong when marking up an existing photo/PDF, where you want to suppress that dynamic adjustment so markup stays visually consistent regardless of mode. In compact width, the tool picker's built-in undo/redo buttons disappear, so provide your own toolbar undo/redo (and support the standard 3-finger undo/redo swipe everywhere, compact or not).

### For Mindlore

Given the roadmap ("full native iPad app + Apple Pencil, handwritten entries" as the third platform):

**Do:**
- Ship the iPad build well before attempting real handwriting: iPad already runs the iPhone codebase adaptively (SwiftUI + the existing multitasking-agnostic design), so the immediate iPad-specific work is making every screen behave correctly across Full Screen and freely resizable Windowed multitasking, at narrow/intermediate/wide widths, with no assumption about which mode is active.
- Convert the tab bar to iPadOS's `sidebarAdaptable` tab-view style once the app has enough top-level areas to feel cramped in a bottom bar at iPad width, the HIG explicitly frames this as the natural upgrade path from a tab bar, and it costs little since SwiftUI's adaptable style handles both bar and sidebar rendering and the person-facing toggle automatically.
- When handwritten entries are actually built: make Scribble available immediately, free, everywhere Mindlore already has a standard `TextField`/`TextEditor` (the entry title field, any plain search field), this is close to a zero-cost win since Mindlore's editor already uses a UITextView-derived `GrowingTextEditor` per the architecture notes; audit whether that custom text view needs manual `UIScribbleInteraction`/`UIIndirectScribbleInteraction` wiring, since it's custom rather than a stock component.
- For actual freehand "handwritten entry" pages (the bigger Pencil feature), build on PencilKit rather than a bespoke ink renderer, it gives the low-latency drawing, tool picker, and undo/redo scaffolding described above for free, and the existing photo-entry "pages" concept (`PageOrderView`, `EntrySection`) is a plausible home for a handwritten-page entry type alongside photographed and typed pages.
- Mirror the "mark the instant Pencil touches down" rule for a handwritten-entry canvas, no "start drawing" button, consistent with how Mindlore already treats voice capture (recording session `ready` → immediate capture on first real input, not on cover-screen open).
- If cross-out/underline/highlight markup on existing entries is ever wanted (e.g., annotating a page scan), use PencilKit's marking tools and suppress Dark Mode's automatic color adjustment for that markup layer, since it's drawn over fixed source content (a photo), not a blank canvas.
- Support pressure-to-opacity or pressure-to-thickness if any freehand tool ships, it's the expected, intuitive mapping and costs little.

**Don't:**
- Don't build a custom text-entry component for the handwriting/Scribble surfaces if a stock text view will do; Scribble's zero-configuration promise only holds for standard components.
- Don't let any transcribed/live Scribble text field auto-scroll or reflow while someone is mid-stroke, this is called out specifically as disruptive, and Mindlore's editor already has related caret-preservation rules (per the architecture notes on `GrowingTextEditor` never reassigning text under an active UITextView) that a Pencil-writing mode would need to extend rather than fight.
- Don't gate Pencil interactions behind a mode switch or toolbar toggle, every "start marking" flow described here assumes Pencil-down is itself the trigger.
- Don't use double-tap, squeeze, or barrel roll for anything destructive (e.g., don't map any of them to "delete entry" or "discard recording"), all three gestures can fire accidentally, and the guidance is explicit that they must map only to easily reversible actions.
- Don't hover-trigger any action (e.g., don't auto-open a preview sheet just because Pencil hovers near a "record" button), hover is for preview only, never for triggering, especially not anything destructive.
- Don't treat iPad multitasking as optional or skippable, "every app needs to work well with multitasking" is stated as close to a hard requirement, with games as the only named exception, and Mindlore isn't a game.
