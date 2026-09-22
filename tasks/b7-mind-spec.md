# B7: Mind's visual pass, and where else iOS 26 belongs

Two pieces. The first is the remainder of B7 from `tasks/phase-b-ux.md`: Mind's glass, halo, Bloom,
replay ticks, and empty state. The second is the audit the owner asked for, one recommendation per
surface, built only where the recommendation says build.

## What is already done, and what B7 actually has left

The plan's B7 line reads "Halos, Bloom, glass, empty state, suggested questions, citation cards".
Three of those shipped without B7 being opened:

- **The kind palette landed in B0.** `Palette.swift:32-47` already has seven fixed asset colours,
  one per `EntityKind`, read by the canvas per fill bucket. There is nothing left to repaint.
- **Suggested questions and citation cards shipped in PR #23** (`AskSuggestions`, the source chips
  under an answer). Ask is done.
- **Glass is proven.** `AskView.swift:314` is the one call site in the app,
  `.glassEffect(.regular.interactive(), in: Capsule())`, and `tasks/b5-b6-spec.md:257` records that
  it compiled on the first try. The plan's old caveat about unverified 26.5 modifier names
  (`phase-b-ux.md:363`) is dead.

What is left is Mind: glass on seven surfaces, a Breathe halo, Bloom for new nodes, a replay tick,
and an empty state that looks designed rather than defaulted.

## The glass pass

Every `.regularMaterial` and `.thinMaterial` in the app, with a verdict against the house rule
(`phase-b-ux.md:93-96`: glass only on what floats over content, never glass on glass, never on list
rows).

| Site | What it is | Verdict |
|---|---|---|
| `SearchPanel.swift:84` | the Mind panel | **Glass.** Named on the list. |
| `MindView.swift:195` | lens menu button | **Glass**, via `.buttonStyle(.glass)`. |
| `MindView.swift:205` | filters button | **Glass**, via `.buttonStyle(.glass)`. |
| `MindReplay.swift:133` | replay play button | **Glass**, via `.buttonStyle(.glass)`. |
| `MindReplay.swift:123` | replay stop chip (date) | **Glass**, and it morphs from the play button. |
| `MindLens.swift:96` | lens legend capsule | **Glass.** It floats over the map. |
| `MindView.swift:464` | the peek overlay's background | **Glass.** See the trap below. |
| `MindView.swift:226` | breadcrumb capsules | **No.** They sit inside a horizontal scroller in a row of their own; six glass capsules in a line is noise, not float. They keep `.regularMaterial`, and the current crumb keeps its tint. |
| `ReflectView.swift:68` | the period control in `safeAreaInset` | **Glass.** It floats over the charts and shipped before this pass existed. |
| `PageStripView.swift:28` | page-number badge on a thumbnail | **No.** It sits on an opaque image, not over content, and it is 4pt of corner radius. |
| `PageOrderView.swift:103` | page tile background | **No.** It is a content tile in a grid, the list-row case. |

**The peek-card trap, resolved.** B5/B6 backed glass out of `EntityPeekCard`
(`b5-b6-spec.md:273-274`) and was right: the card is presented as a partial-height sheet at
`AskView.swift:112` and `EntryEditorView.swift:210`, detents `[.height(220), .large]`
(`EntityPeekCard.swift:21`), and iOS 26 already draws that as glass. But `MindView.swift:464` is a
different presentation of the same card: `MindPeekOverlay` is a plain `VStack` child floating over
the canvas, no sheet anywhere. The glass goes on the overlay's wrapper, never inside
`EntityPeekCard`, so the sheet presentations are untouched. This distinction is the whole of the
change and belongs in a comment beside it.

**Container and morph.** Mind's top bar puts the replay control, the lens button and the filters
button within a few points of each other. Three separate `.glassEffect` calls stack three lenses
side by side; a `GlassEffectContainer` blends them into one sampling pass, which is what the API is
for. Inside it, `@Namespace` plus `.glassEffectID` lets the replay control morph between the round
play button and the wider date chip when a replay starts, instead of one view being replaced by
another. That is `Motion.carry`'s description ("one object moving between two places") applied to
the one place in Mind where a control genuinely changes shape.

**What does not change.** The search field inside the panel keeps `.fill.tertiary`
(`SearchPanel.swift:145`): it is inside the glass panel, and giving it glass is the glass-on-glass
case. Every accessibility identifier stays on the control it is on now. The five Mind identifiers
the UI suite uses (`mindSearchPanel`, `mindFilters`, `mindLens`, `mindReplay`, `mindReplayStop`)
sit on `Button`s and containers whose backgrounds change, not on anything that moves.

## The Breathe halo

**Who breathes.** A node whose entity is named by an entry dated within seven days of the map's
current date. Computed from `MindMapSnapshot.links` (each `LinkInput` carries `entityID` and
`entryDate`), not from `Entity.lastLinkedAt`, for three reasons: it needs no fetch, it is the same
`entryDate` the map's existing 90-day recency weighting already uses (`EntityGraph.build`), and it
takes the replay's `asOf` for free, so a replay's halo moves with the replay instead of sitting on
whoever is recent today. It lands in `MindMap` as a pure function beside `primaryAreas`, and
`MindView.frame` carries it into the `Frame`, so it is unit-testable without a canvas.

**How it draws.** One ring outside the node's own circle, in the node's own colour at low alpha.
The plan's set of ringed node indices goes into `GraphDrawPlan` and therefore into `GraphDrawCache`,
whose key already covers topology, focus, highlight and paint generation; the halo set changes only
when the topology does, so it costs a set build per recompute and nothing per frame. The breathing
itself is one `sin` of the timeline's date per frame, shared by every ringed node, not one per node.
Capped like `glowCap`: the ranked-by-`linkCount` top 40, so a busy week does not ring eighty nodes
and turn the map into a target range. A faded node (a lens dimming it) does not breathe, on the same
grounds the lens fades it.

**Reduce Motion.** `Motion.resolve(.breathe, reduceMotion:)` already returns `nil`, which is the
contract: the ring draws once at mid amplitude and holds still. The canvas reads
`\.accessibilityReduceMotion` and never calls `sin`.

**The idle problem, which needs a decision.** `GraphCanvasView.swift:91` is
`TimelineView(.animation(paused: isIdle))`. The canvas deliberately stops ticking once the
simulation settles and nothing is being touched, which is why Mind does not cook the battery on a
map that has stopped moving. A halo that breathes has to keep the timeline running, so it undoes
that. Three ways out, and the third is the recommendation:

1. Halo breathes only while the canvas is awake, and freezes at mid amplitude on idle. Free, and
   visibly wrong: the thing stops breathing exactly when the user settles down to look at it.
2. Never idle while halo nodes exist. Correct-looking and the most expensive: 60 fps forever on the
   strongest screen in the app.
3. **On idle with halo nodes present, keep ticking at a slow rate** (`.animation(minimumInterval:)`
   around 1/12 s) instead of pausing. A 2.4 s breath at 12 fps is smooth; the per-frame work is one
   `sin` plus 40 ring strokes against a cached plan, and `FrameTimeSampler` plus the existing
   `graph.rendered` event measure it rather than assume it. If the measured work p95 moves, option 1
   is the fallback and the constant's reason gets written next to it, the way the recency floor's
   is.

This is a behaviour change on a phone, so it is flagged: the simulator can show the frame numbers,
and only the device shows what it costs in battery.

## Bloom for new nodes

`BloomTransition` is a SwiftUI `Transition`. Graph nodes are drawn in a `Canvas`, which has no
view identity and no transition system, so `.transition(.bloom)` cannot reach them. The prompt
assumed it could; it cannot. Two honest options:

- **Build it in the draw.** A node's radius scales 0.6 to 1 with opacity over 0.6 s from the moment
  it arrives. That needs a birth time per id and a curve, and since `Animation` cannot be sampled,
  the curve is a small pure `BloomCurve` approximating `spring(duration: 0.6, bounce: 0.3)`, unit
  tested on its own (starts at 0.6, overshoots once, settles at 1 by 0.6 s). Under Reduce Motion it
  is opacity only, matching `BloomTransition`'s own rule.
- **Skip it.** The map already animates a new node outward from its neighbours because
  `GraphSimulation.update` places it there and reheats.

Recommendation: build it, because "the app noticed something" is what Bloom means and a new name
appearing on the map is the clearest instance of it in the whole app. `GraphSimulation` stays
untouched: `MindView.show` already holds the previous frame's node ids and can diff them, passing
`arrived: [UUID: Date]` down to the canvas.

**When it must not fire**, and this is most of the design:

- Not on the first build. Three hundred nodes blooming at once is a firework, not a notice.
- Not on a filter change. Raising the minimum-mentions stepper adds nodes that are not new.
- Not during a replay. Every step adds nodes by construction; the replay is its own animation.
- Only on a `graph.revision` bump that added ids, which is the case the user caused by writing an
  entry.

Stagger (`Motion.stagger`, 60 ms) orders them by `linkCount`, so on the rare multi-node arrival the
better-connected name lands first.

## Replay ticks

`phase-b-ux.md:106-109` specifies "replay tick soft impact at 0.4". The replay runs 100 ms steps for
10 s, so a tick per step is a hundred haptics and a tick per published step (every fifth) is twenty
buzzes of nothing in particular. **A tick fires when the replay's displayed month changes**, which
is the number already on screen in the stop chip (`MindReplay.swift:116`). A two-year journal ticks
24 times over ten seconds, a three-month journal ticks three times, and each tick means something the
user can see. `.sensoryFeedback(.impact(weight: .light, intensity: 0.4), trigger:)` on the month
string, in `MindReplayControls`, where the string already lives.

Haptics do not fire in the simulator. This one is device-only by nature and gets called out rather
than claimed.

## The empty state

`MindView.swift:148-156` is a bare `ContentUnavailableView` with a system hexagon glyph. Designed
version, on the same `Paper` the rest of the app uses: the line in serif, the description in the
app's voice, and a button that starts a recording through the same call the Journal's record button
uses, because an empty map means an empty journal and the only fix is writing something. It keeps a
`ContentUnavailableView` shell so the layout and Dynamic Type behaviour stay free, with `description`
and `actions` filled rather than a hand-built stack. New identifier `mindEmptyState` on it.

There is a second empty state worth the same minute: the map is not empty, but every node is
filtered out. Today that draws nothing at all, an empty screen with a panel. Same shell, different
words, and the action clears the filters.

## The wider audit

One recommendation per surface. Four of these are build-now; the rest are written down with what
they would cost.

**`GlassEffectContainer` + `.glassEffectID` + `@Namespace`.** Fits. Build it, in Mind's top bar
only, for the play-to-stop-chip morph described above. Cost: one namespace and a container wrapper.
Breaks nothing; the identifiers stay on the buttons.

**`.buttonStyle(.glass)` and `.glassProminent`.** Fits, and it is better than what this pass would
otherwise write: a hand-rolled `.frame(width: 40, height: 40).background(.glassEffect, in: Circle())`
has no pressed state, while the style does. Build it for the four Mind controls. `.glassProminent`
is for the one affirmative action on a floating surface; Mind has none (Done buttons live in
`Form` toolbars, which are not floating), so it stays unused. **Do not** put it on the recorder's
stop button: that is B4's screen and its own decision.

**`.tabBarMinimizeBehavior(.onScrollDown)`.** Fits the idea and costs more than it looks. The tab
bar carries the record accessory while a recording runs (`RootView.swift:156`), and minimizing it
on scroll hides the one control that stops a recording in progress. It also puts the tab bar in
a state `app.tabBars.buttons[...]` may not reach, and that query holds up most of the UI suite
(`lessons.md:224-233` is about exactly this class of breakage). Recommendation: **not now.** If it
is wanted, it belongs in its own change with the recording case reasoned about, not inside a visual
pass on another tab.

**`.scrollEdgeEffectStyle`.** Fits, cheaply, in one place: Mind has no scroll view, but the Journal
list now scrolls Today's header under a tab bar and a status bar, and `.soft` is the style meant for
content that should fade rather than hard-clip. Cost is one modifier. It changes what the Journal
screenshots look like, which is a reason to do it in the same pass that reopens them, or to leave it
to whoever next touches Journal. Recommendation: **leave it**, and name it here so it is not
rediscovered. It is not Mind, and "four surfaces done properly" is the instruction.

**`ToolbarSpacer` and the newer toolbar grammar.** The app has 24 toolbars, all of them small: one
or two items, mostly Done and Cancel, inside `Form`s. `ToolbarSpacer` earns its place when a toolbar
has enough items to group, and none here does, except `EntryEditorView.swift:99`'s
`ToolbarItemGroup`, which is already grouped. Recommendation: **no change**, anywhere.

**`.backgroundExtensionEffect`.** It extends an image under a sidebar or an inset. The app has one
full-bleed image surface, the page viewer, which is a `fullScreenCover` with no inset to extend
under. Recommendation: **no candidate**. Written down so the question is closed.

**`.searchable` placement.** Four sites, all inside sheets
(`MergeIntoView`, `RepointView`, `ContactPickerSheet`, `PlacePickerSheet`), all correct as they are.
Mind's `SearchPanel` is deliberately not `.searchable`: it is a pull-up panel with detents and its
results sit beside the content rather than replacing it, which `lessons.md:136-148` records as the
fix for a real bug (swapping a screen's content under an open keyboard drops the next keystroke).
Recommendation: **do not convert it.** This is the one audit item where the modern component is the
wrong answer, and the reason is already paid for.

**`.symbolEffect`.** Four sites today, all in Ask and the Keep card. Two more earn their place in
Mind: `.symbolEffect(.bounce, value:)` on the filters glyph when a filter changes, and
`.contentTransition(.symbolEffect(.replace))` on play becoming stop, which pairs with the glass
morph rather than duplicating it. Build both. Cheap, and they break nothing.

**The record accessory morphing into the recorder.** The obvious candidate, and the survey says it
is not a glass problem. `RootView.swift:159` presents `RecordingView` in a `.fullScreenCover`, and
there is no `matchedGeometryEffect`, no `@Namespace`, and no `matchedTransitionSource` anywhere in
the repo. `.glassEffectID` morphs shapes inside one hierarchy; it does not cross a presentation
boundary. The tool for this is `.matchedTransitionSource` plus `.navigationTransition(.zoom)`, and
the open question `phase-b-ux.md:363-365` raises (whether the zoom transition accepts an overlay as
its source) is still open, because the source here is a system-drawn tab accessory the app does not
own the geometry of. Recommendation: **not in B7.** It is B4's headline item ("Carry transition"),
it is a spike before it is a change, and it lands on the recording screen, which is device-only to
verify.

## Tests and verification

**Unit.** `MindHaloTests` (who breathes, at seven days exactly, at eight, during a replay's `asOf`,
capped at 40 by link count, a faded node excluded), `BloomCurveTests` (start, overshoot, settle,
Reduce Motion), and additions to `MindReplayTests` for the month-change tick predicate. All pure,
none of them need a canvas.

**Screenshots.** `DesignScreenshotTests` today takes six shots and never opens the Mind panel
(`DesignScreenshotTests.swift:55-58` taps the tab, sleeps and shoots). Extend `testTour` with the
panel at `.half`, a peek card up, and the filters sheet, in both appearances. `GraphScreenshotTests`
covers the map's own states. The demo seed cannot produce an empty map, so the empty state needs
its own launch without the seed.

**Then open them.** `xcrun simctl ui <udid> appearance dark` on a booted device before the dark
run, because `XCUIDevice.shared.appearance` does not reach the simulator, and export the attachments
and look at them, because a screenshot's name is not evidence of its content
(`lessons.md:213-222`). Both traps are the reason this section exists.

**Runs.** The unit suite (the CLAUDE.md command) before every push, plus `GraphUITests`,
`GraphCanvasTapping`, `GraphScreenshotTests` and `DesignScreenshotTests`, which are the classes that
open what this changes. Its own simulator, created and targeted by udid, because two worktrees
cannot share one (`lessons.md:113-127`).

**Device.** The replay haptic, the halo's real battery cost, and the glass over a moving canvas are
all hardware-only. The device pass keeps being declined, so each is called out as unverified rather
than assumed working.

## Commits

1. Glass on the Mind panel, the four controls, the lens legend, the peek overlay, and Reflect's
   period control, inside a `GlassEffectContainer` with the play-to-chip morph.
2. The Breathe halo: `MindMap` computation, `GraphDrawPlan` carriage, the ring in the draw, the
   timeline rate decision.
3. Bloom for arriving nodes: `BloomCurve`, the id diff in `MindView.show`, the four rules about when
   it must not fire.
4. The replay tick and the two symbol effects.
5. The two empty states.
6. Screenshot coverage, and `CLAUDE.md` plus `phase-b-ux.md` updated with what landed.

## Owner decisions

1. **The halo's idle cost.** Option 3 (slow tick, measured) is the recommendation. Option 1 (freeze
   on idle) is free and looks wrong. The difference only fully shows on a phone.
2. **Bloom in the canvas at all**, given it needs a hand-rolled curve rather than the transition
   that already exists. Recommendation: yes.
3. **Anything from the audit promoted into this pass.** Recommendation: no.
   `.tabBarMinimizeBehavior`, `.scrollEdgeEffectStyle` and the accessory Carry each belong to a
   screen this pass is not touching.
