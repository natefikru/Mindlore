# HIG notes: navigation, presentation, controls (group 3)

Context: Mindlore is a five-tab app (Journal/Mind/+/Reflect/Chat) with a custom
half-circle "+" fan drawn over the tab bar (NewEntryFan.swift), a bottom
recording accessory (RecordAccessory.swift), sheets for Settings and insights,
a custom pull-up drawer on Mind (SearchPanel/DrawerSurface), Liquid Glass
floating bars throughout, swipe-to-delete with Undo (UndoQueue.swift), and
search surfaces on both Mind and Journal. AppRouter.swift owns tabs and cross-
tab routing; EditorLifecycle.swift governs editor open/close side effects.

## Tab bars

Apple's rules: a tab bar is for navigating between top-level sections, never
for actions (actions belong in a toolbar). Keep the bar visible whenever
people move between sections; hiding it is acceptable only when a modal
covers it, because a modal is temporary and self-contained. Use as few tabs
as it takes to cover the app's sections: more tabs raise navigation cost, and
a sidebar (or a tab bar that converts to one) is the answer for a genuinely
complex hierarchy. Never let tabs overflow into a "More" tab if avoidable;
that hurts discovery. Never disable or hide a tab bar button because its
content happens to be empty right now, explain the empty state inside the
tab instead. Every tab needs a label (single words where possible) alongside
an SF Symbol, filled style preferred, and a red badge is reserved for
critical, action-worthy information only, never routine counts.

On iOS specifically, the tab bar in iOS 26 floats above content at the bottom
on a Liquid Glass background that lets content peek through. Apple explicitly
supports an "attached accessory" pattern (their example: the Music
MiniPlayer) that can minimize the tab bar and move the accessory inline with
it on scroll down, restorable by tapping a tab or scrolling to top
(`TabBarMinimizeBehavior`). A tab bar can include a dedicated search tab at
its trailing end.

For Mindlore:
- The `+` is drawn as a custom overlay centered on the visible bar rather
  than as a real tab, and it never becomes the selected tab (`AppTab.newEntry`
  toggles the fan and writes `tab` back). That is a deliberate, documented
  divergence from "a tab bar is for navigation, not actions": Apple would say
  a tab bar item should navigate, and putting a create-action in the tab row
  is exactly what they warn against for ordinary items. Mindlore's choice
  reads as closer to the system's own affordance for a center "compose"-style
  action (which iOS itself doesn't standardize, unlike a floating action
  button on Android), worth flagging as an explicit, considered break from
  the letter of the rule, not an oversight, since RootView keeps the
  underlying tab live for VoiceOver.
- Five tabs (Journal/Mind/+/Reflect/Chat, four real destinations plus the
  fan) sits at Apple's implied sweet spot ("generally easier to navigate
  among fewer tabs"); no overflow risk.
- RecordAccessory sitting above/near the tab bar and persisting across tab
  changes matches Apple's own "attached accessory" precedent (MiniPlayer) for
  iOS 26's Liquid Glass tab bar, likely a good match, not a divergence,
  though nothing here uses the minimize-on-scroll behavior explicitly (worth
  checking whether RecordAccessory should adopt `TabBarMinimizeBehavior`
  semantics rather than a fully custom presentation).

## Toolbars

Apple's rules: a toolbar carries the view's title, navigation controls (Back,
Close, search), and actions/menus, arranged leading/center/trailing. Choose
items deliberately, don't overcrowd; the system (macOS/iPadOS) auto-manages
overflow, apps must not hand-roll one. Use a "More" menu for lower-priority
actions, but try to fit everything in the toolbar first. Use standard Back
and Close symbols, never a text label reading "Back"/"Close". Prefer
system-provided, borderless symbols for actions (borders are unneeded because
the Liquid Glass section already provides a visible container); reserve text
labels for actions symbols can't clearly represent (e.g., "Edit"). Use
`.prominent` style for exactly one primary action (e.g. Done), placed on the
trailing edge. Cap groupings at about three; never mix a text-labeled button
next to a symbol button without a fixed space between them, or they visually
merge. Titles: useful, under 15 characters, never just the app's name; leave
empty if content already supplies context (their own example: Notes doesn't
title a single open note). iOS: prioritize only the most important items,
push the rest to More; large titles collapse to standard on scroll and
restore at the top, reinforcing location. iPadOS: a toolbar and tab bar can
share the same horizontal space at the top.

For Mindlore:
- Journal's toolbar carries only the Settings gear (per CLAUDE.md, moved
  there deliberately when Settings left the tab bar), this matches "choose
  items deliberately," a minimal, single-purpose toolbar rather than
  overcrowding.
- The insights sheet and Mind's top bar (play button, window control, Tidy
  up) are effectively toolbars with several controls in a
  `GlassEffectContainer`; worth checking they stay under roughly three
  logical groups per the "minimize groups" rule, and that the More-menu
  actions (chat "More menu" entries like "Chat about this entry", "Add a
  name") stay reachable from the main interface too, not toolbar-exclusive,
  per the context-menu overlap rule below.
- The editor hiding the tab bar while the keyboard is up is exactly the kind
  of exception Apple names ("hidden tab bar" only during a modal/keyboard
  cover), consistent with guidance, not a violation, since AppRouter also
  hides the + with it.

## Navigation and search / Searching

(Both landing files are stubs with no body content in this HIG snapshot;
substantive content lives in Search fields below.) Apple's general search
principle, stated in "Searching": if search matters, give it a primary
position (a toolbar field, or a dedicated tab in a tab-bar app like Photos or
Apple TV). Favor one clearly identified search location app-wide; local,
in-view search (a filter) is fine for apps with clearly distinct sections.
Always make the current scope of a search legible via placeholder text, a
title, or a scope bar. Offer suggestions (recent searches, predictive
completions) to speed typing, and let people clear search history for
privacy.

For Mindlore:
- Mindlore has two search surfaces (Journal's list search and Mind's
  SearchPanel drawer) rather than one unified location, Apple explicitly
  allows this ("apps with clearly distinct sections" can have local search),
  but the two should communicate scope clearly (Journal search implicitly
  scopes to entries; Mind's panel scopes to names/entities/tags) so people
  aren't confused about which one to reach for.
- `JournalSearch` falling back to substring search when the ranked BM25 path
  returns nothing is a good implementation of "provide the most relevant
  results first" without silently returning nothing.

## Search fields

Apple's rules: a search field = icon + editable text + Clear button +
placeholder. Search should start filtering as the person types (no explicit
submit step) whenever feasible. Support scope bars (mutually exclusive
category filters) and tokens (selectable/editable term chips) to narrow
scope; default to the broadest scope and let people narrow. iOS placement:
three options, a tab-bar tab (either a "standard" tab with its own landing
page of suggestions, or a "button appearance" tab that jumps straight into
the field+keyboard), a toolbar field (bottom preferred if there's room; top
if bottom space is needed for other content), or an inline field pinned
above the list it searches (best when there's more than one search field in
the app, or location matters to scope). iPadOS/macOS: trailing edge of the
toolbar for split-view apps, or top of a sidebar for filtering
navigation/settings.

For Mindlore:
- Mind's SearchPanel is closer to the "inline field pinned above the content
  it searches, in its own pull-up drawer" pattern than a toolbar or tab
  field, a reasonable custom pattern given Mind is a canvas, not a list, but
  it's a genuinely custom component (`DrawerSurface`), not a system one, so
  none of the detent/grabber/dismiss conventions below (from Sheets) apply to
  it automatically; worth deliberately deciding whether it should behave like
  a resizable sheet (grabber, drag-to-dismiss) since it visually resembles
  one.
- Journal search and Mind search should stay visually and behaviorally
  distinct paths (per "navigation and search" above) given they query
  different things (entries vs. entities); confirm placeholder text names
  what's being searched in each case.

## Sheets

Apple's rules: a sheet is for a scoped task tied to the current context.
iOS/iPadOS sheets can be modal or nonmodal (nonmodal: person acts on the
parent through the sheet without dismissing it, e.g. Notes' formatting
sheet). Standard buttons: Cancel/Close (dismiss without saving, leading
edge), Done (dismiss after completing/saving, trailing edge), Back
(multi-step flows only, never a dismiss action). Always pair a Done button
with a Cancel or Back, never leave Done as the only way out. Never show all
three (Cancel, Done, Back) together. Show only one sheet at a time from the
main interface: close the first before presenting a second triggered from
within it. Detents: system defines `large` (full) and `medium` (~half);
sheets get `large` automatically, add `medium` to allow resting at half
height for progressive disclosure (their example: a share sheet), omit
`medium` when full content needs full height (their example: compose sheets
in Mail/Messages). A resizable sheet needs a grabber (drag to resize, tap to
cycle detents; also a VoiceOver affordance). Support swipe-to-dismiss; if
there are unsaved changes, confirm via an action sheet before discarding.
iPadOS: prefer page or form sheet presentation styles for a consistent
default size.

For Mindlore:
- Settings and the insights sheet both look like single-view sheets: confirm
  each follows Cancel/Done-or-plain-Close-only conventions per screen (e.g.,
  Settings' root likely just needs a Close/Done, not a Back+Cancel
  combination, since it's five simple rows each pushing further).
  EntryInsightsView is explicitly "a sheet over the editor, never a push," so
  it should get a grabber/drag-to-dismiss treatment consistent with a
  resizable sheet if it supports partial-height presentation; if it's a
  fixed full-height sheet with only a scroll view (as CLAUDE.md describes,
  "a scroll of InsightCards on Paper"), that's consistent with "no medium
  detent when full content needs full height."
- Settings is a sheet presented from a gear icon in Journal's toolbar, and
  its five rows push further screens within that sheet (General, AI, Your
  journal, Today and reminders, About), this is a multi-step flow inside one
  sheet, which is exactly the "subsequent step" and "final step" button
  placement case Apple calls out (Back appears, Cancel/Done placement can
  vary by depth); worth double-checking each pushed screen doesn't
  accidentally show a redundant Cancel alongside Back.
- "AISettingsSheet presents itself rather than routing... so nothing presents
  over a sheet that is still closing" is precisely Apple's rule: "display
  only one sheet at a time... if something people do within a sheet results
  in another sheet appearing, close the first sheet before displaying the
  new one." Mindlore already encodes this correctly.

## Alerts

Apple's rules: reserve alerts for critical, actionable information; never
alert merely to inform (find another way, e.g. an inline indicator). Never
alert for common, undoable/reversible destructive actions (e.g. routine
delete with Undo available), only for uncommon, non-undoable destructive
actions. Never alert on app launch. Title: complete and specific but under
two lines, sentence-style caps + punctuation if a full sentence, title-style
without punctuation if a fragment; avoid "Error" as a title. Buttons: one or
two words, verbs describing the result ("Erase", "Reply"), never
unexplained "OK" except for purely informational alerts, always "Cancel" (not
"No") for a cancel action. Place the likely/default button trailing (row) or
top (stack); Cancel leading/bottom. Use destructive red style only for a
button whose action the person did NOT deliberately choose (e.g. an alert
interrupting them); don't destructive-style a button that performs exactly
the action they intentionally initiated (their "Empty Trash" example). If
there's a destructive action, always include a Cancel escape; never make
Cancel the default (Return-triggered) button. On iOS, prefer an action sheet
over an alert for choices tied to an intentional action (alert = unexpected
interruption, action sheet = expected menu of outcomes for something you
did).

For Mindlore:
- Given Mindlore's own UndoQueue pattern (5-second delayed delete, swipe or
  toolbar Delete both routed through it), Mindlore is already doing exactly
  what Apple asks: "avoid alerts for common, undoable destructive actions."
  The one deliberate exception, JournalWipe ("the one delete with a
  confirmation dialog instead of Undo"), is the correct use of a
  confirmation surface precisely because it's the uncommon, non-undoable
  case Apple calls out.
- AIConsent (the "Allow" alert naming OpenAI before enabling AI) is a good
  fit for alert semantics: critical, actionable, not routine, needs explicit
  confirmation before an action with real consequences (data leaving the
  phone), matches "confirm a purchase or other important action."
- Any "delete conversation" or "discard recording" confirmation should be
  checked against whether it's common+undoable (skip the alert, use Undo) vs.
  uncommon+permanent (alert is right).

## Action sheets

Apple's rules: use an action sheet, not an alert, for choices tied to an
intentional action the person just took (their canonical example: canceling
an in-progress Mail draft offers Delete Draft / Save Draft, not a warning
alert). Keep titles to one line; skip the message unless it adds real
information beyond title+context. Include a Cancel button (bottom on iOS)
when the sheet might destroy data; SwiftUI's `confirmationDialog` includes
Cancel by default. Destructive choices get the destructive (red) style and
sit at the top of the sheet, most noticeable position. Never let an action
sheet scroll; if it has too many choices it's the wrong component. On iOS,
use an action sheet, not a menu, for choices that appear as a direct
consequence of an action (menus are for things people choose to reveal).

For Mindlore:
- Discarding a ready-but-unstarted recording, or "third-step" flows like
  page-order cancellation, are candidates for action sheets rather than
  alerts if the choice is "what do you want to do with what you started"
  (Save / Discard / Keep Editing), check whichever confirmation currently
  covers "closing a recorder with content" against this pattern; if it's
  currently an alert, action sheet is likely the more correct component per
  Apple's own Mail-draft example.
- Swipe-to-delete plus Undo means most delete confirmations are already
  correctly skipped; action sheets should only appear where there's a
  genuine multi-way choice, not a single confirm/cancel (that's still an
  alert's job when non-undoable, per Alerts above).

## Popovers

Apple's rules: use for a small amount of transient info or a few closely
related actions; don't blow up the popover to hold everything. Point the
arrow directly at the revealing control; don't cover that control or content
the person needs while the popover is open. Close button (Cancel/Done) only
when needed for clarity (e.g., saving vs. discarding); otherwise popovers
dismiss on outside tap or on selecting an item. Always save nonmodal-popover
work before an accidental outside-tap dismiss discards it; only an explicit
Cancel should discard. Show only one popover at a time, never a
popover-from-a-popover cascade. Nothing may render on top of a popover except
an alert. On iOS/iPadOS, avoid popovers in compact width; use a full-screen
sheet instead in compact layouts.

For Mindlore:
- EntityPeekCard is described as opening "also as a partial-height sheet
  that iOS 26 already draws as glass", that's consistent with the
  compact-width guidance (avoid true popovers in compact iPhone width, use a
  sheet-like presentation instead), so the choice of sheet over popover for
  the peek card on iPhone is correct per HIG rather than a shortcut.
  MindPeekOverlay is worth checking against "point at the revealing
  element, don't cover it."

## Menus / Pull-down buttons / Pop-up buttons

Menus (general): title-style capitalization, drop articles, verb/verb-phrase
labels for actions, ellipsis suffix when the action needs more input before
completing. Icons: use consistently within a group (all items in a group get
one, or none do); use only recognized standard icons. Organize by
frequency/importance first, group logically with separators, aim for ≤3
groups worth in a small menu; move to submenus only when a term repeats
across 3+ items in one group, and keep submenus to one level. Show
unavailable items dimmed (not hidden) in a general menu, so people can still
discover the command exists, a context menu is the opposite (hide, don't
dim, see below). Toggled items: a single item with a changing label
(Show/Hide X) rather than two, add a verb if the state-vs-action reading is
ambiguous.

Pull-down button: menu of actions/items related to the button itself (e.g. a
Sort button's list of sort attributes, an Add button's list of item types).
Needs at least ~3 items to be worth the extra tap; 1-2 items should be plain
buttons or toggles instead. Never dump all of a view's actions into one
pull-down, primary actions must stay directly visible. Destructive items in
red, confirmed via an action sheet (iOS) or popover (iPadOS) on selection.

Pop-up button: for a flat list of mutually exclusive options/state (not
actions), use pull-down instead if the choices are actions, allow multiple
selection, or need a submenu. Always show a sensible default/current
selection.

For Mindlore:
- The editor and insights sheet "More menu" entries (Add a name, Chat about
  this entry, entry-kind picker, cleanup Review/apply) are a good fit for a
  standard menu: verb-led labels, logically grouped, not overloaded.
  `EntryKindPicker` (life/note/creative) is a textbook pop-up-button use
  case: mutually exclusive states, not actions, confirm it's implemented as
  a picker/menu with the current kind shown, not a pull-down-styled control.
- Any "Sort" or "Filter" control on Journal's list (life-area filters, Notes
  chip, Creative chip) reads more like a scope-bar/segmented pattern than a
  pull-down; worth confirming those aren't hidden inside a single pull-down
  menu, since Apple explicitly prefers visible primary filters over buried
  ones.

## Context menus / Edit menus

Context menu rules: reveal via long-press/pinch-and-hold (iOS/iPadOS/
visionOS) or secondary click (macOS/iPadOS+trackpad). Keep it short and
relevant to the specific item, not a dumping ground for advanced/rare
actions. Every context-menu action must also exist somewhere in the main
interface (Apple: "Always make context menu items available in the main
interface, too"), a context menu can never be the *only* way to reach a
command. Hide unavailable items entirely (don't dim, unlike a regular menu).
Destructive items go at the end, marked destructive (red). Don't show a
title unless it clarifies (e.g. "3 messages selected"). On iOS/iPadOS,
provide either a context menu or an edit menu for an item, never both, since
the system can't disambiguate intent. A context menu can show a content
preview above the command list.

Edit menu rules: strongly prefer the system-provided edit menu (Copy/Cut/
Paste/Select/Look Up/etc.) over a custom one; reveal it the standard way
(touch-and-hold or double-tap to select, then the compact horizontal bar,
expandable via chevron into a full context menu on iPad with keyboard/
trackpad). Only show commands relevant to current selection state (no Copy
with nothing selected, no Paste with nothing to paste). List custom commands
after the system ones, in the same visual style. Support undo/redo for
anything an edit-menu command does.

For Mindlore:
- Every context-menu command in Mindlore (entry row swipe actions, entity
  row actions, chat "More" items) should be double-checked against "must
  also exist in the main interface", e.g. if "Delete entry" is only in a
  swipe/context menu and not also reachable via the editor's own More menu,
  that's worth calling out, though CLAUDE.md does note the editor's own
  Delete entry goes through AppRouter.deleteEntry, so this is likely already
  satisfied for entries.
- The read-mode `GrowingTextEditor` linking mentioned names as `.link`
  attributes opening a peek on tap sits outside the standard edit-menu
  system; confirm normal text selection/copy still works over that same
  text (Apple: "let people select and copy noneditable text").
- Mind's card/row swipe actions and any long-press on a Mind node/tag should
  follow the "hide unavailable, don't dim" rule, distinct from the general
  Menus rule of dimming.

## Pull-down buttons / Pop-up buttons

(Covered together with Menus above; no additional Mindlore-specific notes
beyond those already listed.)

## Buttons / Segmented controls

Button rules: minimum 44x44pt hit target (iOS), always show a press state.
Use a prominent (accent-colored) style for the single most likely action per
view, cap prominent buttons at one or two per screen, more raises cognitive
load. Distinguish preferred choices by style, not by size (never make two
buttons in a set different sizes to imply preference). Roles: Normal,
Primary (the default/likely choice, Return-triggered, closes sheets/alerts
automatically), Cancel, Destructive. Never assign Primary role to a
destructive action even if it's the likely choice, people click Primary
without reading; use a distinct label instead. iOS: buttons performing
non-instant actions can show an inline activity indicator and a
changed label ("Checkout" → "Checking out...") rather than a separate
progress view.

Segmented control rules: for a small set (≤5 on iPhone, ≤5-7 wide) of
closely related, mutually exclusive choices affecting one object/view/state;
alternatively can act as a stateless row of action buttons (rare, mostly
macOS). Never mix selection-state segments with action segments in the same
control. Keep segment widths/content sizes even; text-only or icon-only, not
mixed. Use noun/noun-phrase labels, title-style caps, no intro label needed.
On iOS, appropriate for switching between closely related subviews (not
top-level app sections, that's a tab bar's job).

For Mindlore:
- Reflect's Life/Recaps/Loose ends segmented control is exactly the
  canonical iOS use case: "switch between closely related subviews," ≤5
  segments, mutually exclusive, in the nav bar. Good match.
- Mind's kind chips (All, People, Places, Projects, Themes) in SearchPanel
  read more like filter chips than a true segmented control (they filter a
  list/map rather than switch subviews), and CLAUDE.md doesn't say they're
  mutually exclusive with a single active state visually distinct the way a
  segmented control is, worth confirming they're either implemented as a
  segmented control (if truly single-select) or intentionally a different
  chip component if multi-select-adjacent.
- The editor's `.prominent` action, if any (e.g. a Done button closing the
  editor sheet-like presentation), should stay singular per screen; check
  Settings sheet screens don't accumulate more than one prominent button.

## Lists and tables / Collections

Lists/tables rules: prefer lists for text content (rows are easy to scan);
switch to a collection/grid only for image-heavy or widely-size-varying
content. Support reordering where it makes sense even without add/remove.
Selection feedback should differ by purpose: persistent highlight for
navigation-hierarchy lists, brief highlight + checkmark for option lists.
Keep row text short to avoid truncation/wrapping; consider showing a title
only, deferring detail to a detail view. On iOS/iPadOS, an info/detail-
disclosure button reveals more info about a row but must never double as
hierarchical navigation, use a chevron disclosure indicator for drill-down,
never both an index and trailing-edge accessories/disclosure indicators on
the same list (the two compete for the same touch target on the trailing
edge).

Collections rules: use standard row/grid layouts, avoid custom ones that
confuse or draw attention to themselves; prefer a table over a collection
for primarily textual content. Give generous padding around image items so
focus/hover/tap effects don't overlap or obscure neighbors. iOS/iPadOS:
avoid changing a collection's layout while someone is actively interacting
with it, unless in direct response to an explicit action.

For Mindlore:
- The Journal entry list (title, preview text, kind badge, date) is a
  textbook list-not-collection case, consistent with Apple's "prefer lists
  for text." Two lines of `previewText` plus badges matches "keep item text
  succinct."
- Mind's map (Canvas/force-directed) is neither a list nor a standard
  collection grid, it's explicitly a custom visualization, which HIG
  doesn't really cover; the SearchPanel's `MindRankedRow` list underneath it
  is the actual "list" surface and should follow list conventions (it
  appears to, per CLAUDE.md's description of rows with kind badge,
  sparkline, count).
- Page strip (photographed pages in the editor) may be closer to a
  horizontal collection (image-based) than a list, appropriate per "ideal
  for image-based content."

## Scroll views / Page controls

Scroll view rules: support default gestures/keyboard shortcuts, elastic
bounce; make it visually apparent content continues beyond the fold (partial
content peeking at the edge). Never nest two scroll views with the same
axis. Consider a page-by-page scroll mode where content is naturally chunked.
Auto-scroll only to preserve context (search hit, cursor entering a hidden
area), and only just enough to restore visibility, not more. Scroll edge
effects (the blur/opacity transition where a floating bar meets scrolling
content) should be one per view, automatic style preferred, and exist only
to keep floating controls legible over scrolling content, not decorative.

Page control rules: for a flat, ordered set of pages (not hierarchical);
center at the bottom; cap around 10 dots, more than that needs a grid
instead. Customize indicator images sparingly (at most one distinct type for
a single specially-meaningful page, e.g. "current location"); never recolor
indicators (breaks contrast). On iOS, background styles: automatic (only
during interaction, for non-primary navigation), prominent (always visible,
only when the page control is the primary nav for the whole screen), minimal
(no background, no scrubbing support).

For Mindlore:
- Today's horizontal card row ("2 of 9" under it) is functionally a page
  control / paged scroll view. Confirm the "2 of 9" text label plus dots (if
  present) doesn't duplicate a system page-control indicator on the same
  axis (Apple explicitly warns against showing both a page control and a
  scroll indicator on the same axis, redundant).
- The editor's single scroll view (header + GrowingTextEditor) matches "one
  scroll view," and the tab-bar/toolbar Liquid Glass floating over it is
  exactly the intended use case for a scroll edge effect, worth confirming
  Journal's list, Reflect's charts, and Mind's drawer all use a system scroll
  edge effect rather than a custom fade, per "prefer the automatic style."
- SearchPanel's cross-fade-to-opaque-Paper-over-48pt is a custom variant of
  what the scroll-edge-effect guidance addresses (visual separation between
  floating chrome and scrolling content); it's a reasonable bespoke
  implementation of the same underlying goal, not a violation, since the
  panel isn't literally a system toolbar.

## Layout and organization / Presentation

Both HIG landing pages are empty stubs in this snapshot (no body content
beyond the title); no rules to extract. They function as index/category
pages in the live HIG (linking to sub-pages like Sheets, Popovers, Modality,
Split views, etc., most of which are covered by their own dedicated files
elsewhere in this notes set or a sibling group).

## Progress indicators

Apple's rules: use determinate whenever a duration is knowable (helps people
decide whether to wait); indeterminate only for genuinely unquantifiable
work. Be honest and even-paced with determinate progress, don't let it race
to 90% then crawl. Keep an indicator visibly moving; a stationary indicator
reads as a freeze. Never switch between the circular (spinner) shape and the
linear bar shape mid-task, pick one and stay consistent for that operation.
Show a short, specific status string only if it adds real information
("Transcribing" beats nothing but "Loading" adds nothing). Put a progress
indicator in a consistent, predictable location. Offer Cancel when halting
is safe, and Pause + Cancel when partial progress would otherwise be lost.
Warn before discarding progress on cancel. iOS pull-to-refresh: still run
automatic periodic background updates too, don't make manual refresh the
only path; a title on the refresh control should describe the content
("last updated at...") not explain the refresh gesture itself.

For Mindlore:
- Transcription, insights generation, and Ask's streaming answer are all
  good determinate/indeterminate candidates: CLAUDE.md notes Ask's first
  sentence lands within about a second and the answer streams in, that's
  effectively a determinate-feeling experience via the streaming text
  itself, which is arguably a better solution than a generic spinner (Apple
  favors determinate over indeterminate when feasible, and streaming content
  is the most determinate feedback there is).
- Redo insights ("count and Stop") on Settings' AI screen matches "let
  people halt processing" + expose a determinate count, aligning well with
  the HIG's own guidance to prefer determinate indicators with a Cancel/Stop
  affordance for a long-running batch operation.
- Any bare spinner shown during OpenAI calls (title generation, transcription
  fallback) that never becomes determinate is acceptable per Apple (they
  allow indeterminate for genuinely unquantifiable network calls), but
  should never silently swap shape from spinner to bar mid-operation if a
  UI later adds a progress bar for chunked audio uploads (AudioChunker),
  since chunk count is knowable and a determinate bar would fit that case
  better than a spinner.

## Disclosure controls

Apple's rules: use to hide detail/advanced options until relevant, keeping
frequently used things visible by default. Disclosure triangle: points
inward (leading) collapsed, down expanded; needs a descriptive label naming
what's hidden ("Advanced Options"), not just an icon. Disclosure button
(separate from the triangle): points down collapsed, up expanded, sits next
to the specific control it affects, and a view should never contain more
than one disclosure button (multiple create ambiguity about which content
belongs to which button). Available on iOS/iPadOS/visionOS via SwiftUI's
`DisclosureGroup`.

For Mindlore:
- EntityView being "a Form that leads with insight" and pushing admin
  actions (rename, kind, aliases, contact info) behind a toolbar Edit rather
  than an in-page disclosure group is a reasonable alternative pattern (a
  dedicated edit mode rather than progressive disclosure inline), and avoids
  the "more than one disclosure button" trap entirely by not using
  disclosure controls there at all.
- If Settings' Advanced AI screen (model fields, cloud fallback, custom
  prompts) ever collapses "advanced" fields inline rather than as a full
  separate screen, a single `DisclosureGroup` labeled clearly ("Advanced")
  would be the correct component per this guidance, rather than hiding those
  fields behind an unlabeled chevron or a second unrelated push.
