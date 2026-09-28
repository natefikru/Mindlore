# HIG notes: input, system integration, and monetization

> Checked against the code on 2026-09-27: the API key field is already a `SecureField` (`AISettingsView.swift`), recording uses `.record` (`AudioRecorder.swift`) so the silent switch cannot drop capture, and playback uses `.playback` with `.spokenAudio`, which pausing music on playback is right for. Treat those three bullets below as resolved.

Group: text views, text fields, keyboards, virtual keyboards, entering data, pickers, toggles,
sliders, labels, gestures, drag and drop, charts, charting data, playing audio, file management,
collaboration and sharing, activity views, widgets, Live Activities, App Shortcuts, Siri,
Home Screen quick actions, controls, system experiences, snippets, Apple In-App Purchase,
ratings and reviews, camera control.

## Text views

A text view is for long, editable, or specially formatted text; a label is for short static
text, a text field for short editable text. Mindlore's editor (`GrowingTextEditor`, a UITextView)
is squarely a text view. Rules: keep text legible, adopt Dynamic Type, test with Bold Text on.
Make useful text selectable (error messages, IDs), the read-mode entry view already allows
selection since it's a plain non-editable UITextView. iOS: show the keyboard type appropriate to
content (see Virtual keyboards below); this doesn't really apply to free-form journal text, but
matters for any text field elsewhere in Settings (email, URLs).

**For Mindlore:**
- Nothing to change in the editor itself; the app already treats the journal body as a text view,
  not a label or field.
- Any settings field that takes an email or URL (none currently) should get the matching keyboard
  type per Virtual keyboards, not `.default`.

## Text fields

Use a text field for short, specific input (a name, a title). Show a hint via placeholder text
("Email") plus, where the placeholder disappears once typing starts, a persistent label. Size
the field to the expected content length. Use a secure field for passwords (n/a, Mindlore has no
passwords; API key entry could be a candidate but Mindlore stores the OpenAI key in Keychain via
a paste field, not a system password prompt, worth checking whether it should be a `SecureField`
for shoulder-surfing protection). Validate dynamically, at the right moment (blur for email-style
fields, before switching away for anything the user is actively composing). Use a number
formatter for numeric fields rather than assuming manual parsing. iOS specifics: show a trailing
Clear (x) button on a text field so people can erase input in one tap; use leading icon for
purpose, trailing icon/button for extra function (e.g., a bookmark).

**For Mindlore:**
- The API key field in AI settings should be a `SecureField` (obscured, like a password) since it
  is sensitive and currently likely a plain `TextField`; worth a direct check against HIG's "use a
  secure text-entry field when appropriate" rule.
- Entry title field, custom name fields (life area renames, "how you're written about") should
  have Clear buttons and appropriately sized widths, small, single-line inputs, not full-width
  text-view-style fields.

## Keyboards (physical)

Mostly a macOS/iPad concern: Full Keyboard Access, standard shortcuts (Cmd-Z undo, Cmd-B bold,
etc.), custom shortcuts only for the most frequent app-specific commands, ordered Control-
Option-Shift-Command when combined. iPadOS explicitly says: support keyboard navigation in text
fields, text views, and sidebars, but avoid custom keyboard nav for buttons/switches/segmented
controls, let Full Keyboard Access handle those instead.

**For Mindlore:**
- The format bar (bold/italic/heading/list) is a natural candidate for Cmd-B/Cmd-I/Cmd-U shortcuts
  when a hardware keyboard (iPad or Mac Catalyst-style) is attached, since these map to standard,
  expected shortcuts rather than new ones.
- Not urgent given Mindlore is iPhone-first; revisit if/when the "native iPad" roadmap phase (see
  Platform roadmap memory) lands.

## Virtual keyboards

Match keyboard type to content semantics: `.emailAddress`, `.URL`, `.numberPad`, `.decimalPad`,
`.namePhonePad`, etc. Setting a `textContentType` also improves autofill/autocorrect quality, not
just the key layout. Customize the Return key (e.g., `.search`, `.done`) to match the action taken
when it's pressed. Custom input views/accessories should only appear when they add real value and
should stay visually consistent (adopt Liquid Glass to match a Liquid-Glass-toolbar app). Use the
keyboard layout guide so custom controls sit correctly above the keyboard rather than fighting it.

**For Mindlore:**
- The `FormatBar` inputAccessoryView is exactly the "custom controls above the keyboard" case HIG
  describes, CLAUDE.md already notes it adopts Liquid Glass, which matches guidance directly.
- Settings text fields for name/API key etc. should each set an explicit `keyboardType`/
  `textContentType` (email, URL, or default with autocorrection off for a key) rather than
  leaving them on system defaults.

## Entering data (general)

Pre-fill and pre-fetch anything the system already knows (location, calendar, defaults) rather
than asking. Be explicit with placeholder/label text about what's wanted. Never prepopulate a
password field. Prefer choosing from a list (picker/menu) over typing when that's viable. Support
drag-and-drop and paste as alternate entry paths. Validate as people go, and gate "Next/Continue"
buttons until required fields are filled rather than letting people press ahead and fail later.

**For Mindlore:**
- Life areas, entry kind, and mood are already picker/toggle driven rather than typed, matches
  the "offer choices instead of requiring text entry" principle well.
- The onboarding/welcome flow (Add a key) and any future paywall sign-up screen should validate
  the key/consent state before enabling "Continue," matching the gating rule.

## Pickers

Use a picker for medium-to-long lists; a short list should be a menu/segmented control instead,
a very large one a searchable list. Order values predictably (alphabetical, chronological).
Avoid switching screens just to show a picker, show it in place, near the field it edits. iOS
date pickers come in four styles (compact, inline, wheels, automatic) and four modes (date, time,
date+time, countdown up to 23h59m); use compact when space is tight.

**For Mindlore:**
- `EntryKindPicker` and life-area selection are already inline, in-context choices, good fit.
- The entry date editor (`entryDate`, "use the suggested date automatically") should use a compact
  or inline `DatePicker` rather than pushing to a separate screen, consistent with "avoid
  switching views to show a picker."

## Toggles

A toggle communicates one of two opposing states. In a list row (iOS), use the switch style with
no extra label, the row content is the label. Outside a list, use a button that behaves like a
toggle (background/highlight change), not a switch. Never rely on color alone to convey on/off, also change fill, shape, or an inner glyph. Changing the default green switch color is fine if it
still contrasts against the off state.

**For Mindlore:**
- Settings rows (Use AI, Format voice notes automatically, recordOnOpen, etc.) are already
  standard list-row switches, correct per HIG.
- Any toolbar-style toggle-like control (e.g., a future "mute" or "hide" affordance outside a
  list) should be a highlighted button, not a switch control, per the iOS platform note.

## Sliders

Minimum on the leading/bottom side, maximum on trailing/top, never reverse this. Consider
pairing a wide-range slider with a text field and stepper for exact values. iOS: never use a
generic slider for audio volume, use `MPVolumeView` (a dedicated volume view with output-route
switching) instead of building a custom volume slider.

**For Mindlore:**
- No slider currently in the app (the audio player has a scrubber, which is a distinct case from
  a "value slider," but the direction rule, minimum leading, maximum trailing, playhead moves
  left to right, still applies and matches standard behavior).
- If a future preference needs a range value (e.g., digest length, cache size), pair it with a
  stepper/text field rather than a bare slider if precision matters.

## Labels

Static, often-copyable text. Four semantic label colors: label (primary), secondaryLabel
(subheading/supplemental), tertiaryLabel (unavailable item text), quaternaryLabel (watermark).
Prefer system fonts/Dynamic Type; if using a custom font ensure it stays legible at all sizes.

**For Mindlore:**
- `Entry.previewText` (list row secondary lines) and other secondary UI text should map onto
  `secondaryLabel`/`tertiaryLabel` semantics rather than arbitrary opacity-reduced primary text,
  for correct Dark Mode and accessibility contrast behavior.

## Gestures

Support alternate input methods; never gate an important action behind one specific gesture.
Standard iOS gestures beyond the universal set: three-finger swipe (undo/redo), three-finger pinch
(copy/paste), four-finger swipe (iPad app switching), shake (undo/redo). Custom gestures should
be discoverable, simple, distinct, and never the *only* way to do something important. Any
shortcut gesture (e.g., edge-swipe back) should supplement, not replace, an explicit control
(e.g., a Back button).

**For Mindlore:**
- The + button's "hold and slide to a fan option" interaction (`NewEntryFan`) is a custom gesture
  layered on a system-standard tap, it satisfies "supplement, don't replace" since tapping the +
  still works and each option is independently reachable.
- Swipe-to-delete on entry rows and swipe paging in Today's card row are both standard gestures,
  already aligned.

## Drag and drop

Support it broadly if built on system text views/fields (mostly free via UITextView/UIKit).
Provide non-drag alternatives (menu commands) since drag-and-drop isn't always feasible for
everyone. A drop within the same container is a move; a drop into a different container (or a
different app) is a copy. Show a translucent drag image, highlight valid drop targets, animate
failed drops (evaporate/return). Support multi-item drag where useful.

**For Mindlore:**
- Not currently a feature; low priority. If cross-entry text move/copy or dragging a photo into
  an entry from Photos becomes a feature, the move-within/copy-across-container default applies,
  and it's free to a good extent via standard UITextView/UIKit drop delegate integration.

## Charts / Charting data

**Charts (anatomy and mechanics):**
- A chart = marks (bar/line/point) + scales + axes + descriptive content (title, subtitle,
  legend, annotations). Bar marks for comparing categories/sums; line marks for change-over-time
  trend; point marks for showing distribution/outliers/relationships. Combine mark types when it
  adds clarity (e.g., points on top of a line to call out specific values).
- Axis range: fixed range when min/max are inherently meaningful (0-100% battery); dynamic range
  when values vary and you want marks to fill the plot area. Bar charts should usually use a
  zero-based Y axis so bar heights are visually comparable; a non-zero baseline can better reveal
  small but meaningful differences (e.g., heart rate).
- Prefer familiar tick sequences (0, 5, 10…) over arbitrary ones (1, 6, 11…).
- Maximize plot-area width in compact layouts; keep vertical-axis labels as short as possible,
  consider putting a category label inside the plot area instead of a wide axis label.
- Accessibility: every chart needs accessibility labels (Swift Charts gives default per-mark
  labels); enable Audio Graphs; write labels with context (not bare numbers), avoid subjective
  words ("rapidly," "almost"), avoid ambiguous formats/abbreviations ("June 6" not "6/6", spell
  out units). Hide visible axis/tick text labels from VoiceOver since Audio Graphs covers it.
  Expand tap targets so small marks are still scrubbable; make chart keyboard/Switch-Control
  navigable in a logical order (e.g., along the X axis, or by subset rather than every point for
  huge datasets).
- Color: never rely on color alone to distinguish series, pair with shape/pattern too. Add
  visual separators between adjacent color blocks in stacked bar charts.

**Charting data (when/why to chart):**
- Not every dataset needs a chart, use a list/table if you just need to present data without
  analysis. Use a chart specifically to highlight a message. Keep it simple; let people opt into
  more detail (progressive disclosure) rather than cramming a chart full of data. Prefer common
  chart types (bar, line) people already know how to read. Add descriptive headline/summary text
  above or beside a chart (a chart never replaces the need for accessibility labels though). Keep
  visual consistency across multiple charts of the same dataset (same type, color, style) so
  people can transfer understanding between them; deviate only to highlight real differences.

**For Mindlore:**
- Reflect's mood/area charts and Mind's sparklines should audit against: zero-based Y axis for bar
  comparisons, accessibility labels with context (not raw numbers), and color-plus-shape pairing
  for mood categories (moods are currently color-coded, check whether a shape/icon backs it up
  for colorblind users).
- The 16-bucket sparkline in `MindStats` is glanceable-chart territory; per "charting data," a
  one-line summary headline above it (already partly served by "what changed" text) is the right
  pattern to keep.
- Reflect's narrative text generation is itself the "descriptive summary" HIG recommends pairing
  with a chart, good alignment already.

## Playing audio

Respect system silent switch and volume, apps must not override system volume, only apply
internal relative mixing. Use `MPVolumeView` for a volume control, never a custom slider. Support
audio output rerouting (AirPlay/Bluetooth) unless there's a strong reason not to. Choose the right
`AVAudioSession.Category`:
- **Solo ambient**: nonessential sound, silences other audio, respects silent switch, no
  background play (a game soundtrack).
- **Ambient**: nonessential, doesn't silence others, respects silent switch, no background.
- **Playback**: essential sound, ignores silent switch, can background-play (audiobooks).
- **Record**: recording only, ignores silent switch, can background-record (note-taking apps with
  audio recording, this is Mindlore's core category for capture).
- **Play and record**: simultaneous record+play, ignores silent switch, can background.
Respond to external audio controls (Control Center, headphone buttons) only when actively
relevant, don't hijack them when idle. Handle interruptions (calls, etc.) explicitly: decide
whether an interruption should be resumable and whether to auto-resume when it ends.

**For Mindlore:**
- Voice recording (`AudioRecorder`) should be on `.record` (or `.playAndRecord` while a player is
  also active) so it ignores the silent switch, worth verifying the actual category chosen, since
  a wrong category (e.g., `.ambient`) would silently drop capture when the ring switch is off,
  a serious bug for a journaling app.
- Playback of recordings (RecordAccessory / entry audio player) should check whether it needs to
  mix with other apps' audio (probably yes: journaling audio playback shouldn't kill music), `.playback` with `.mixWithOthers` or a similar option is worth an explicit check.
- The 10s-skip and scrubber mentioned as an editor follow-up (memory: Editor follow-ups) already
  matches "consider custom player controls only if the system doesn't support what you need", standard skip increments aren't system-provided, so custom controls here are justified by HIG.

## File management

Mostly about document-based apps with Open/Save panels and a file browser, not very applicable
to Mindlore's SwiftData-backed single-journal model. Key transferable points: avoid making people
explicitly save (autosave, Mindlore's `EntrySaver` already does this); Quick Look can preview
files your app can't otherwise open (relevant to page-photo attachments or exported files).

**For Mindlore:**
- `JournalExport`'s output folder and `JournalImport`'s file picker are the one real touch point;
  no changes indicated, HIG's iOS 18 "document launcher" pattern doesn't fit a non-document app.
- If exported `.json`/media files ever need previewing before import, a Quick Look integration
  would be low-effort and idiomatic, but not currently needed.

## Collaboration and sharing / Activity views

**Collaboration and sharing:** built around CloudKit/iCloud Drive sharing, the Collaboration
button, and SharePlay, this is a multi-person editing model. Not applicable to Mindlore today
(the CloudKit sync is single-user, private, journal-mirroring only, not a shared document). Keep
on file for if a future "shared entry" or family/therapist-sharing feature is ever considered, would use the same ShareLink/CloudKit-sharing pattern HIG describes (permission summaries, a
Collaboration button placed next to Share).

**Activity views (share sheet):** Use the Share button to trigger the system share sheet, never
build a custom alternative for the same action. App-specific actions should get a title and
optionally a custom SF Symbol; avoid duplicating actions the system already provides (e.g., don't
add a custom Print action). For a time-consuming background task started from a share/action
extension, continue it and let people check status in the main app rather than notifying just for
completion.

**For Mindlore:**
- Journal export (`JournalExport`) or a single-entry "Share" (e.g., share an entry as text/PDF)
  should route through the standard share sheet (`ShareLink`) with a clear custom title (e.g.,
  "Export Entry"), not a bespoke UI, if/when such a feature is added, none exists today per
  CLAUDE.md's Views section, so this is a gap/opportunity rather than a fix.

## Widgets

**Sizes and where they appear (iOS-relevant):**
- System family: Small, Medium, Large (iPhone/iPad); Extra Large and Extra Large Portrait
  (iPad/Mac/Vision Pro only, not iPhone).
- Accessory (Lock Screen / complications): Circular, Corner, Inline, Rectangular. On iPhone/iPad,
  Lock Screen supports Circular, Inline, Rectangular (not Corner, which is watch-only).
- Standard margin: 16pt for most widgets; 11pt for tighter internal groupings. Smaller margins
  used on Lock Screen/StandBy automatically by the system.
- Text: 11pt minimum font size; use real text elements (never rasterize text) so Dynamic Type
  (Large through AX5) and VoiceOver both work.
- Widget gallery description: start with an action verb ("See...", "Keep track of..."), never
  "This widget shows..." or "Use this widget to...".
- Widgets can be interactive (buttons/toggles) without opening the app, but tapping anywhere else
  always opens the app to the specific related content, never a generic app-open.
- Widgets should show glanceable, changing content, not something static (a static widget is just
  a bigger app icon and people remove it).
- StandBy/CarPlay: use small-widget layout with background removed and scaled up; avoid rich
  color/background, just large legible text on black.

**For Mindlore:**
- A Lock Screen/Home Screen widget is a real gap. Candidates that fit "dynamic, glanceable, deep
  links to specific content": (1) today's loose-end or Today-card content (rectangular accessory
  or small system widget, deep-linking straight to that loose end/entry), (2) a "days since your
  last entry" or streak-free "last entry" glance (matches Mindlore's explicit no-streak stance, About screen already avoids streaks, so a widget should similarly avoid guilt-driven framing
  and instead show something like the day's open thread or word-count-free encouragement).
- An interactive widget with a "New Entry" or "Start Recording" button (Reminders-widget-style
  toggle/button pattern) would let people capture without opening the app, directly matches the
  App Intents already built (`New Written Entry`, `Start Recording`).
- Because widgets can't update in real time, the Live Activity (below) is the better fit for an
  in-progress recording, not a widget.

## Live Activities

**Hard limits and mechanics:**
- Intended for activities lasting up to about 8 hours; a well-behaved app ends the Activity the
  moment the task/event truly ends.
- Locations: Lock Screen, Home Screen banner, Dynamic Island (compact/minimal/expanded), StandBy,
  Mac menu bar (via iPhone Mirroring), Apple Watch Smart Stack, CarPlay Dashboard.
- Presentations to design for: Compact (Dynamic Island, two elements either side of the camera),
  Minimal (when 2+ Activities are active, reduced to icon/short value), Expanded (touch-and-hold),
  Lock Screen (bottom banner, similar layout to Expanded).
  - Compact: keep content narrow and snug to the TrueDepth camera cutout, no padding against it;
    leading/trailing elements must read as one unit (shared color/typography) and link to the same
    destination when tapped.
  - Expanded: wrap content tightly around the camera cutout.
  - Lock Screen: standard margin 14pt; don't replicate a plain notification layout, make it
    Activity-specific; default light/dark background unless a custom color is chosen (must work in
    both appearances and Always-On reduced luminance/Night Mode's red tint).
- Ending: Dynamic Island/CarPlay remove immediately at end; Lock Screen/menu bar/Watch Smart Stack
  keep it visible up to 4 hours, set a deliberate custom dismissal time proportional to the
  activity, commonly 15-30 minutes.
- Alerts: only for updates people truly shouldn't miss; don't also send a push notification for
  the same update (redundant); an alert plays sound and shows the expanded/banner presentation.
- Interactivity: keep to a single interactive element if any (avoid accidental taps); good uses
  are pause/resume/cancel-style controls for something people start once and let run (music,
  workout, an active microphone recording).
- No ads/promotions; never show sensitive content directly (redact and require a tap-through to
  the app for anything private) since Live Activities are visible to anyone glancing at the
  device.
- Animations max 2 seconds; none play during Always-On reduced-luminance.
- App Shortcuts should be offered to start a Live Activity (e.g., via the Action button).

**For Mindlore:**
- A Live Activity for an in-progress voice recording is a strong, clearly HIG-sanctioned fit: it's
  a bounded activity (well under 8 hours), benefits from Dynamic Island/Lock Screen visibility,
  and a single Pause/Stop control matches the "one interactive element" recommendation. It also
  reduces the risk of someone losing track of an active recording when they've left the app (the
  in-app `RecordAccessory` already exists, a Live Activity would extend that same state to the
  Lock Screen/Dynamic Island rather than requiring the app to be reopened).
- Because Mindlore's recordings are private journal content, keep the Live Activity content
  generic ("Recording…", elapsed time) rather than showing any transcribed text, matches the
  "avoid displaying sensitive information" rule directly, and journaling is about as sensitive as
  content gets.
- End the Activity the instant `stop()` fires (ingestion begins), with at most a short custom
  dismissal window (a few minutes, not the default up-to-4-hours) since there's nothing useful to
  show once recording stops.

## App Shortcuts

- Up to 10 App Shortcuts per app; each wraps one or more App Intents into a single user-facing
  action, immediately available even before first launch.
- Each App Shortcut may take at most one optional parameter (not several), keep phrase and voice
  interaction simple ("Start [morning, daily, sleep] meditation" is the complexity ceiling; asking
  for two parameters in one phrase is discouraged).
- Phrase must include the app name; keep it brief and memorable, with natural variants.
- If a request is missing an optional parameter, ask a clarifying follow-up or default sensibly
  (e.g., most-recently-used option) rather than failing.
- Order App Shortcuts by importance in code, determines default Spotlight/Shortcuts ordering
  until usage data reprioritizes them.
- Editorial: "App Shortcuts" and "Shortcuts" are title case and capitalized/plural when referring
  to the system feature; lowercase "shortcut" when referring to an individual user-made shortcut.
- Prefer adopting an App Schema domain over custom App Shortcuts when the app's functionality fits
  an existing domain (messaging, media, etc.), schemas get free Apple Intelligence/Siri
  integration without per-shortcut work. App Shortcuts remain the right tool for functionality
  outside existing schemas.

**For Mindlore:**
- Currently 3 App Intents/Shortcuts (Start Recording, New Written Entry, Ask Your Journal), well
  under the 10 limit, room to add more (e.g., "Add a name" recall, "Open Reflect," a specific loose
  end) if usage data suggested value.
- "Ask Your Journal" could take the one allowed optional parameter (a topic/question string)
  rather than only filling the field after opening, worth checking whether it already does; if
  not, this is a small enhancement matching HIG's "add flexibility with one optional parameter."

## Siri

- Apps become Siri/Apple-Intelligence-aware only by adopting App Intents (actions) and App
  Entities (content); optionally also adopting an App Schema domain for deeper built-in handling.
- Use terminology people would naturally say, pick between "track/song/podcast"-style synonyms
  based on what your users would actually say.
- Only donate content that's personally relevant (recent, favorited) unless the category
  legitimately needs full-catalog exposure (email, messaging), don't dump the entire dataset into
  Spotlight indiscriminately.
- No advertising or upsell language in anything Siri surfaces or speaks.
- Response writing: concise, standalone-audible dialogue (someone might be on AirPods with no
  screen); avoid gendered pronouns in follow-up questions ("Who should I send it to?" not "What's
  his or her name?"); omit the app's own name from responses (system already attributes it);
  device-independent wording since a request can start on one device and finish on another; ask an
  open-ended clarifying question rather than reading out a long list of options.
- "Hey Siri" is only partially localized (only "Hey" translates; "Siri" never does), irrelevant
  to app copy unless Mindlore ever writes onboarding copy referencing the phrase, in which case use
  the exact locale table from the source, not an invented translation.

**For Mindlore:**
- Ask Your Journal's Siri responses (if any spoken dialogue exists) should avoid restating the
  app name and stay concise, matching the pattern above.
- Entities worth donating to Spotlight are naturally scoped already (entries, entities), the
  bigger question is whether hidden/muted entities and draft entries are excluded from any future
  Siri/Spotlight surfacing, which they should be, mirroring the existing AskSources eligibility
  rules already enforced for chat.

## Home Screen quick actions

- Up to 4 quick actions per app; each icon should be a familiar SF Symbol (never emoji, which
  breaks Dark Mode monochrome + contrast expectations); title should be a short, self-explanatory
  action phrase ("New Message," not the app name or vague text); an optional subtitle can add
  context (e.g., unread count). Quick actions can update dynamically (e.g., recent items) but
  changes should be predictable, not surprising.

**For Mindlore:**
- Currently no Home Screen quick actions defined. Natural candidates mapping directly onto the
  existing App Intents: "New Entry," "Start Recording," "Ask Your Journal", 3 of the allowed 4,
  giving a fourth slot free for something like "Open Reflect" or a rotating "recent loose end."
  This is a near-zero-cost extension of work already done for Siri/Shortcuts (same App Intents can
  usually back both).

## Controls (Control Center / Lock Screen / Action button)

- A control (Control Center tile, Lock Screen control, Action button assignment) is a button or
  toggle backed by an SF Symbol, a title, and optionally a value; the amount shown depends on
  where it's placed (Control Center at larger sizes shows title+value, Lock Screen shows symbol
  only, Action button shows symbol + value in the Dynamic Island on press-and-hold).
- Toggle controls need distinct on/off symbols (e.g., `door.garage.open`/`door.garage.closed`),
  animated at the state transition; button controls with a duration should animate while running
  and stop when done.
- Require authentication/unlock for anything security-sensitive; redact title/value (and
  optionally the symbol state) when the device is locked if the content is sensitive.
- Controls that need setup should prompt for configuration the first time they're added.
- Provide hint text (a verb phrase) for what the Action button does on press-and-hold.

**For Mindlore:**
- A "Start Recording" Control Center tile / Lock Screen control / Action button assignment is a
  direct, clean fit, matches an existing App Intent, requires no configuration, and needs no
  redaction (the control itself reveals nothing about content, just "start/stop recording").
  This is one of the more concretely actionable additions from the whole HIG group: it's
  low-effort (wraps `Start Recording`) and materially reduces the number of taps to capture a
  thought, matching Mindlore's "capture friction" priority.
- A toggle-style control isn't a great fit (recording isn't really a toggle you'd flip from
  Control Center mid-session), better as a button control that launches straight into recording.

## System experiences

Source file for this topic is a stub with no body content in the current HIG export (title only,
no guidance text), nothing substantive to extract.

## Snippets

- Snippets are the compact confirmation/result views Siri or an App Shortcut shows after an
  action; two types: confirmation (Cancel + a labeled primary action button, used before doing
  something) and result (single Done button, shown after).
- Hard limit: custom view content must fit within a 400-point maximum height.
- Keep content short; for a result snippet needing more detail, deep-link into the app rather than
  cramming detail into the snippet.
- Give the confirmation snippet's primary button a specific, task-named label ("Order," not "OK"
  or "Proceed"); default is "Continue" if unspecified.
- Don't rely on the spoken dialogue text to convey the snippet's purpose visually, the custom
  view itself should communicate that; the dialogue is primarily for audio-only contexts.

**For Mindlore:**
- If "New Written Entry" or "Ask Your Journal" ever returns a snippet (e.g., confirming an entry
  was created, or showing a short Ask answer inline from Siri), respect the 400pt cap and use a
  specific primary button label ("Save," "Start Recording") rather than a generic one.
- Given Ask's answers can run long, a snippet is the wrong vehicle for showing a full Ask
  response, deep-link to the Chat tab instead, per "deep-link to content in your app instead of
  including it in the custom view."

## Ratings and reviews

- Ask for a rating only after demonstrated engagement (a completed task/session), never on first
  launch or during onboarding.
- Never interrupt an active task to ask.
- Space repeated requests out, at least a week or two between prompts, and only after further
  engagement.
- Use the system-provided `RequestReviewAction` prompt, not a custom one, it silently checks
  whether the person already responded, and the OS hard-caps the prompt to 3 occurrences per app
  per 365-day period regardless of how many times the app calls the API.
- Resetting the app's summary rating on a new version is possible but trades "reflects current
  version" against "fewer total ratings shown," which can itself discourage downloads.

**For Mindlore:**
- A natural trigger point: after someone's Nth entry (e.g., 10th or a week of regular use), or
  after their first completed Reflect/Life reading, a moment of demonstrated value, not
  onboarding. Given the 3-per-365-days system cap, there's no real risk of over-prompting even if
  Mindlore calls the API somewhat liberally at good moments (the system enforces the ceiling).
- Nothing currently in the codebase around `RequestReviewAction` per the app's feature list, this
  is a clean, low-effort addition for the paid launch (a happy first-week or first-month user is a
  good target for the first ask).

## Camera Control (iPhone 16/16 Pro hardware button)

- Only supported on iPhone 16 and 16 Pro-family hardware; not on iPad, Mac, Watch, TV, or Vision
  Pro, a light press opens an overlay from the bezel; a light double-press reveals adjustable
  controls (a slider, e.g. contrast, or a discrete picker, e.g. grid on/off); sliding a finger
  along the button adjusts the selected control's value.
- Use only SF Symbols (no custom symbols supported) to represent each control; symbols represent
  function, not current state.
- Keep control names short since labels follow Dynamic Type and can crowd the viewfinder.
- Include units/context in slider values (EV, %, or a short custom string).
- Define "prominent values" (commonly chosen or evenly spaced points, e.g., major zoom increments)
  so the slider is more likely to land exactly on them.
- Leave the viewfinder itself free of duplicate controls already present in the overlay.
- A locked-device Camera Control launch is possible via a "locked camera capture" extension, using
  the same in-app camera UI so the transition feels seamless, but any task beyond capture itself
  requires unlocking.

**For Mindlore:**
- Directly relevant to the Pages/photo-page-capture feature (`PageOrderView`, VisionKit capture).
  If Mindlore ever ships a from-the-lock-screen "capture a journal page" flow via Camera Control,
  this section is the reference; today there's no locked-camera-capture extension, and it's a
  reasonable, hardware-gated (iPhone 16/16 Pro only) future nice-to-have rather than a near-term
  priority given its narrow device support.
- Not worth building custom slider/picker controls in the Camera Control overlay for page capture
  specifically, the system's standard zoom/exposure controls likely suffice for photographing a
  journal page; a custom control (e.g., "flatten/perspective-correct") would only be worth adding
  if Mindlore's photo capture flow gains a capture-time-only adjustable setting.

## Apple In-App Purchase (directly relevant to the $7.99/$49.99 launch)

**Purchase types:** consumable, non-consumable, auto-renewable subscription, non-renewing
subscription. Mindlore's $7.99/$49.99 pricing (per GTM memory) suggests either a one-time
non-consumable unlock plus/or an annual auto-renewable subscription, worth deciding explicitly
against these four categories since presentation rules differ by type.

**Core presentation rules:**
- Let people experience the app before paying, support some free access ahead of a paywall
  (freemium, metered paywall, or free trial are the three sanctioned shapes).
- Design the purchase/paywall flow to feel like part of the app, not a bolted-on storefront.
- Product names/descriptions: simple, non-truncating, non-wrapping, plain language.
- Always show the total billing price for every purchase, regardless of type.
- Hide or explain-and-hide the store when the person can't pay (parental restrictions), rather
  than showing a dead-end paywall.
- Use the system's default purchase-confirmation sheet unmodified, never a custom replica.
- Sign-up screen must include: subscription name, duration, and what's included per period; the
  correctly localized billing amount; a way to sign in / restore purchases. Also link Terms of
  Service and Privacy Policy.
- Free trial: explicitly state both the trial duration and the amount billed automatically when it
  ends.
- Encourage subscribing only when not already subscribed (check status first, and support sign-in
  across apps/web if the same subscription is sold elsewhere, so no one is asked to pay twice).
- Provide a "Redeem Code" affordance if using offer codes (custom or one-time-use); custom codes
  are ASCII-alphanumeric only, no special/non-Latin characters, and can't be redeemed directly
  from App Store account settings, the app or a redemption URL must handle this, so the app
  should say so explicitly if it supports it.
- Cancellation must always be easy to find and complete without leaving the app (or, minimally,
  via the system's `showManageSubscriptions` sheet), burying or obscuring cancel is explicitly
  against guidance. Reminding a canceling subscriber what they'd lose, or offering a win-back deal
  after cancellation, is fine; making cancellation itself hard is not.
- Refunds: apps may present custom help UI before a refund request (help articles, alternative
  fixes, identifying the specific purchase) but must not speculate about Apple's refund decisions,
  and must not obstruct or bury the actual refund-request action, which always routes through the
  system's own flow (`beginRefundRequest`).
- Family Sharing: if supported, say so explicitly in product names/sign-up copy ("Family" /
  "Shareable"), and tailor in-app messaging for both the original purchaser and family members who
  receive shared access.

**For Mindlore:**
- Decide and document (in the release plan) which purchase type $7.99 and $49.99 map to, e.g., a
  one-time non-consumable "lifetime" purchase versus a monthly/annual auto-renewable pair, since
  the presentation rules (trial disclosure, renewal language, restore-purchases button) only apply
  to the subscription path.
- Given "Release plan" memory notes on-device insights are free at launch with a paid unlock, the
  paywall should be framed as a metered/freemium model (free journal + free on-device AI, paid
  unlocks something specific like OpenAI-backed insights/Ask, or removes a cap) rather than a hard
  wall, this matches "let people experience your app before making a purchase" directly and also
  fits the app's existing "free journal, no lock-in" ethos noted elsewhere in CLAUDE.md.
- Whatever the mechanism, a Restore Purchases control and (if subscription) a link to the system
  manage-subscriptions sheet are both mandatory checklist items before launch, not nice-to-haves.
