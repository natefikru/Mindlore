# HIG notes: behavior group (accessibility, inclusion, writing, privacy, generative-ai, machine-learning, playing-haptics, feedback, loading, launching, onboarding, offering-help, undo-and-redo, modality, settings, managing-notifications, notifications, icloud, managing-accounts)

> Checked against the code on 2026-09-27: the iCloud "warn before deleting" rule is about documents in file-based apps. The Alerts page says not to alert for common, undoable deletes, so UndoQueue is consistent with the HIG, not a divergence.

## Accessibility (beyond Dynamic Type / AX-size, per owner's exclusion)

Rules:
- Contrast: WCAG AA minimums Apple's own Accessibility Inspector checks: 4.5:1 for text up to 17pt, 3:1 for 18pt+ or any bold text. Must hold in both light and dark. If default contrast doesn't meet this, provide a higher-contrast variant when Increase Contrast is on.
- Prefer system-defined colors (they carry their own accessible variants for Increase Contrast and light/dark).
- Never convey information with color alone: pair with shape, icon, or text for state changes (mood colors, kind colors, etc.).
- VoiceOver: describe interface and content; label controls properly (also feeds Voice Control and Switch Control, which rely on the same labels).
- Hit targets: default 44x44pt on iOS, minimum 28x28pt. Padding: ~12pt around bezeled elements, ~24pt around non-bezel elements to avoid mistaps.
- Simple gestures preferred; avoid custom multi-finger gestures as the *only* way to do something core. Always offer a button alternative to a swipe-to-dismiss or swipe gesture.
- Reduce Motion: when on, cut automatic/repetitive animation (zoom, scale, peripheral motion). Tighten springs, track animations to gesture directly, avoid z-axis depth animation, replace x/y/z transitions with fades, avoid animating into/out of blurs.
- Avoid time-boxed UI that auto-dismisses on a timer (banners, toasts) for anyone needing more time to process or using assistive tech; prefer explicit dismissal.
- Full Keyboard Access / Switch Control: don't override system keyboard shortcuts; make sure custom controls are reachable and labeled.

For Mindlore:
- The whole app leans on color for a lot of meaning (mood colors, kind colors in `EntityKind.color`, kind badges), check each color-coded element also carries a shape/icon/text cue, not just hue (tag pins already do this with shape; mood arcs and area colors should be checked).
- `Motion.bloom`, Mind's canvas animations, GraphSimulation motion, and BloomCurve are exactly the kind of "automatic/repetitive" motion Reduce Motion should suppress; worth confirming these key off the system setting.
- Undo pill, banners (RestoreBanner, KeepCard), and TidyUpButton auto-dismiss timers, if any, should default to explicit dismissal rather than a timeout, per the cognitive-accessibility guidance on time-boxed UI.

## Inclusion / Writing

Concrete rules:
- Address people directly as "you"/"your," not "the user." Reserve "we"/"our" for the software/company, and avoid it in error messages ("Unable to load content," not "We're having trouble...").
- Avoid jargon/technical terms without defining them; avoid colloquialisms (culture-specific, hard to translate, some carry exclusionary history).
- Be judicious with humor: hard to translate, risks annoying repeat viewers or offending others.
- Gender: avoid unnecessary gendered language/pronouns; use gender-neutral nouns; only ask a person's gender if functionally required, and if so, include nonbinary/self-identify/decline-to-state options.
- Represent diverse people/settings when depicting humans; avoid stereotypical occupation/gender pairings.
- Avoid assumption-laden security questions or context-specific prompts that not everyone can answer (Apple's own example: "make of your first car" vs. "favorite activity").
- Writing style: active voice, verbs on buttons ("Send" not "Let's do it!"), no "Click here" links, be clear and cut extra words, read text aloud to check clarity.
- Capitalization: pick title case or sentence case per element type, use consistently.
- Possessive pronouns ("My", "Your") mostly unnecessary, drop them ("Favorites" not "Your Favorites") unless used consistently.
- Empty states: never leave a blank screen without a next step; empty states are temporary, so don't put critical info only there.
- Error messages: no blame, say what to do ("Choose a password with at least 8 characters" not "That password is too short"), skip "oops"/"uh-oh".
- Settings labels: describe what happens when a setting is ON; don't also explain the OFF state, it's implied.
- Multi-step flows: consistent verbs, "Get Started" to begin, "Continue"/"Next" mid-flow, "Done" to finish.

For Mindlore:
- Journal, Mind, Reflect, Ask/Chat copy generally already addresses "you" (Ask's system prompt explicitly does this); worth an audit pass on Settings labels and AI consent copy for stray "we"/passive voice.
- "Format voice notes automatically," "Suggest entry dates," and other Settings toggles should be checked against the ON-state-only description rule, CLAUDE.md's own wording style already favors this, so likely already compliant, but worth a listing check when doing the pass.
- Empty states (Mind's empty state, Ask's empty screen with three suggestions, Today's empty state) look aligned with "give people a next step" already; the AI consent alert and error copy (AIError codes) are good candidates to check for blame-free phrasing.

## Generative AI (high-value: Mindlore sends journal text to OpenAI)

Concrete rules:
- Keep people in control: let them dismiss unwanted AI content, revert/retry transformations, know when AI is used. Never let people think they're talking to/reading content from a human when it's AI.
- Ensure a good experience even without the AI feature (non-AI fallback) when feasible.
- Transparency: clearly communicate where AI is used; set expectations on what it can/can't do up front (tutorial, curated example prompts); explain limitations before they bite, and explain *why* a result was inferior when it happens.
- Privacy specifics (core for Mindlore):
  - Choose model type balancing privacy vs. capability: on-device keeps data on the device, responds fast, works offline; server-based needed for more power/context.
  - For server-based processing: process as much as possible locally, minimize what's shared, be transparent that info may go to a server, show what's shared, explain what may be stored off-device or used for training.
  - Ask permission before using personal information/usage data; use minimum data needed; always offer a clear opt-out. Explicit permission for anything stored/used for model improvement.
  - Model outputs can inadvertently contain sensitive info, be aware.
  - Clearly disclose how the app/model use and store personal data; explain benefits concisely when asking permission.
- Hallucinations: minimize by scoping requests tightly; avoid asking a model for "factual" info unless verified; communicate that AI content may contain errors; never use AI output where a hallucination could cause real harm.
- Irreversible actions: get confirmation before AI performs anything destructive or hard to undo on someone's behalf (don't auto-delete, don't auto-purchase).
- Output handling: make it easy to refine/revert generated content (Edit, Undo, Retry, Adjust near the content); confirm when a correction took effect; if blocked/undesirable output occurs, coach toward a better next attempt rather than a dead end.
- Latency: generative calls are slow, design a loading state or generate in background. Give *specific* progress messages ("Finding substitutions for ingredients," not "Processing…"), this materially beats vague spinners.
- Consider offering multiple alternative results instead of one, when it gives people meaningful choice.
- Feedback loop: let people give simple explicit feedback (thumbs up/down) on AI output, voluntary and unobtrusive, and act on it.
- Architect for model-swapping: decouple UI from the specific model/provider so upgrades don't require redesign.

For Mindlore:
- AIConsent (Views/AIConsent.swift) already names OpenAI and what it gets, gated behind explicit Allow, matches "explain benefits, get explicit permission" almost exactly; the CLAUDE.md line about App Review 5.1.2(i) already assumes this.
- "Consider giving specific, reassuring feedback during generation" is a real gap check: confirm Ask's spinner-to-streaming states and Insights/Transcription progress use concrete phrasing rather than generic "Processing…" (Ask already streams the first sentence within ~1s per CLAUDE.md, which is aligned; other passes like Redo insights show a count, which is good, but check title/insights generation copy for genericness).
- The note-writing paths in Chat (AskNoteWriter) and cleanup auto-apply are exactly the "irreversible-ish action on someone's behalf" case; confirm there's always a clear Undo/Revert path (there is: originalText/cleanupAppliedHash, note edits gated to whole-answer, etc.), good alignment, but the HIG angle argues for keeping that reversibility visible/discoverable, not just structurally present.

## Machine learning (Apple's mental model, not generative-specific)

Concrete rules:
- Classify each ML feature along five axes to decide UX treatment: critical vs. complementary (does the app still work without it), private vs. public data sensitivity, proactive vs. reactive (unsolicited results get less tolerance for low quality), visible vs. invisible, dynamic vs. static (does it improve from user interaction).
- Explicit feedback: request only when necessary; always voluntary; use plain outcome-based language for feedback options ("Suggest less pop music," not "dislike"); act immediately and persist; consider multiple, progressively specific options.
- Implicit feedback: secure it like any sensitive data; disclose that behavior in one place can affect another; don't let it collapse people into a feedback loop that kills exploration; use multiple signals to avoid misreading intent; prioritize recent behavior over old; don't offer sensitive-topic suggestions on shared devices.
- Calibration (one-time setup like Face ID scan): only require it if the feature truly can't work without it; explain why you need it (what it does, not how); collect the minimum; do it once, early; make progress and success clear; let people cancel anytime with no guilt; let them edit/redo the calibration data later outside of the flow.
- Mistakes: anticipate them, give people a way to correct them easily, and consider whether to learn from a correction. Match the correction affordance to the severity of the mistake. Never rely on corrections as a crutch for consistently low-quality output.
- Confidence: only surface confidence if you've verified it correlates with actual quality. Translate into people's mental categories (e.g. "high chance"/"low chance") rather than raw percentages, except in domains where people expect numbers (weather, sports, polling). For proactive/suggestion features, set a confidence floor below which nothing is shown.
- Attribution ("Because you...") should be factual/behavioral, not emotional or presumptive ("Because you've read nonfiction," never "Because you love nonfiction"). Avoid being so specific it feels surveilled, or so generic it feels useless.
- Limitations: set expectations before use for high-impact-but-rare limitations; show good-usage patterns proactively (placeholder text hinting at valid input, live feedback while using a feature); explain *why* a result is weak when it happens; consider telling people when a known limitation has been fixed.

For Mindlore:
- Insights/mood/thinking-pattern classification is "private, complementary, mostly invisible, semi-dynamic", the HIG axis framework argues these should tolerate low confidence quietly (never surfaced) rather than confidently asserting a mood or pattern that's wrong; matches the existing floor-based gating in Life (3 entries minimum, explicit early-read flag) reasonably well.
- Ask's retrieval/citations are effectively an "attribution" surface, the rule "keep attributions factual, not emotional" lines up with the existing ban on the model narrating its own retrieval ("say what you are looking at" was explicitly removed per CLAUDE.md).
- AskDates/EntityResolver "unsureAmong" ties and Mind's "Which one?" review question are a textbook implementation of the calibration/mistake-correction pattern (guided correction, not freeform), good alignment, no action needed.

## Feedback

Concrete rules:
- Feedback types: current status, success/failure of a task, warnings about negative-consequence actions, chance to correct a mistake.
- Match delivery weight to importance: passive status info can sit quietly in the UI; a possible-data-loss warning needs to interrupt.
- Use multiple channels (color + text + sound + haptics) so feedback reaches people regardless of how they use the device (silenced, VoiceOver, not looking at the screen).
- Warn only when data loss is unexpected/irreversible; don't warn for expected deletions (the Finder doesn't warn on every delete).
- Confirm completion only for significant actions people don't already expect to succeed (Apple Pay, not routine saves), over-confirming is noisy.
- When a command can't be carried out, say why (Maps example: same start/end location).

For Mindlore:
- UndoQueue's non-blocking, no-confirmation delete (5-second undo window) matches "don't warn on expected data loss" precisely, the philosophy the app already follows.
- Insights/AI failure states (AIError, permanent-failure banners) should be checked against "explain why a command can't be carried out," since AIError deliberately carries codes only, never provider text; make sure the mapped user-facing string is still specific enough to be useful, not just "Something went wrong."

## Loading

Concrete rules:
- Best loading experience finishes before anyone notices. Show *something* immediately (placeholder/skeleton) rather than a blank screen.
- Let people do other things while content loads in the background.
- For unavoidably long loads, give something interesting to look at (progress detail, tips), sized to the actual wait.
- Use determinate progress when duration is knowable, indeterminate when not.
- watchOS specifically avoids loading indicators; not relevant to Mindlore (iOS only).

For Mindlore:
- Ask's move to streaming responses (first sentence in ~1s, per CLAUDE.md) is a direct implementation of "show something as soon as possible" instead of a spinner on blank screen, already done.
- Transcription/insights/title generation queues run in the background while the rest of the app stays usable, matches "let people do other things while loading." Confirm there's no place left with a bare spinner and no content (e.g., initial insights sheet open before first generation) that could show a placeholder card instead.

## Launching

Concrete rules:
- Launch instantly; people won't wait more than a couple seconds.
- Launch screen must be nearly identical to the first real screen (same solid color, same orientation/appearance) to avoid a "flash"; no text (won't localize), no logos/branding, no artistic expression, it's not a splash screen.
- Restore previous app state on relaunch (scroll position, last view) so people don't retrace steps.
- Launch in the current device orientation.

For Mindlore:
- `RootView` restoring to the previously open tab/entry aligns with "restore previous state"; worth double-checking the launch screen (if customized) matches Journal's actual first-paint background exactly, including light/dark, to avoid a flash.
- The story/demo seed launch args are a dev-only concern, not user-facing; no action needed against this guideline.

## Onboarding

Concrete rules:
- Ideal onboarding: none needed, learned by doing. If required, make it fast, fun, optional, and separate from launch (comes after launch finishes).
- Prefer contextual tips (TipKit-style, tied to the specific UI element/task) over one big onboarding flow.
- If a flow is required, keep it skippable; if skipped once, don't show again unprompted, but keep it discoverable later (help/settings/account area).
- Keep onboarding scoped to the app's own experience, not general OS/device teaching.
- Splash screens (if used) should be brief, just long enough to register, not felt as a delay.
- Don't let big downloads block first use.
- Don't put licensing/legal text inside onboarding, let the App Store handle that.
- Postpone nonessential setup/customization; ship good defaults so most people never need to configure anything.
- If the app needs a private-data permission to function, bake the request into onboarding and explain the benefit there; otherwise ask contextually the first time the specific feature is used.
- Don't ask for ratings or purchases before people have had a chance to get value from the app.

For Mindlore:
- Mindlore's model of "learn by writing, no gate" plus contextual asks (AIConsent shown at the Use AI switch / key save, mic permission presumably requested at first recording) matches "ask contextually, not up front" well.
- Worth confirming there's no forced multi-screen tour blocking first entry; if there's a welcome screen with "Add a key," check it's skippable and that AI is genuinely optional to use the app (it is, per CLAUDE.md: on-device insights work with no key).

## Offering help

Concrete rules:
- Match help depth to task complexity: inline one-line help for simple tasks, a real tutorial only for complex multistep ones. Always dismissible.
- Keep help language/imagery consistent with the actual platform and current input context.
- Don't explain how standard system components work, only explain your app-specific behavior.
- Tips (TipKit): use for simple features completable in ≤3 steps; keep to 1-2 sentences, action-oriented; use eligibility rules so a tip about an already-used feature doesn't show; throttle frequency (e.g., once per 24h) when multiple tips exist; prefer filled icon variant when pairing an icon with a tip; don't duplicate an icon that's already directly connected to the UI it points at; add a button to jump straight to relevant settings or docs when useful.
- Tooltips (macOS/visionOS): keep to 60-75 characters, sentence case, lead with a verb, don't repeat the control's own name, no ending punctuation unless needed.

For Mindlore:
- iOS-only app, so tooltip guidance is moot, but the tip-cadence guidance (throttle, eligibility, don't re-show a tip for something already used) is directly relevant to any future "New in this feature" nudges (e.g., a first-use tip for Add a name, Chat about this entry, or the play-button Mind replay), none are currently mentioned as TipKit-based, worth considering if such nudges get added later.

## Undo and redo

Concrete rules:
- People expect to be able to keep undoing (don't cap it) since a logical checkpoint (opening a doc, last save).
- Help people predict what an undo/redo will do before or as it happens (label it: "Undo Typing," not just "Undo"); on iOS the shake-to-undo alert needs a one-or-two-word suffix after the "Undo"/"Redo" prefix.
- If the undone/redone content isn't currently visible, scroll/reveal it so the action visibly registers, otherwise people think nothing happened and repeat it.
- Consider a "revert all changes since X" bulk option for batches of related edits.
- Don't redefine the standard iOS undo gestures (shake, three-finger swipe); dedicated undo/redo buttons are for when system gestures aren't enough, and should use standard system symbols in a toolbar.
- watchOS/tvOS: undo/redo isn't supported there at all, not relevant to Mindlore.

For Mindlore:
- `UndoQueue`'s 5-second grace window is a different, simpler pattern than classic multi-level undo (closer to Gmail's "Undo Send"), which is fine for the delete-only scope it covers; the HIG's "let people undo multiple times" doesn't really apply here since it's a single pending action at a time, not a stack, worth noting this is a deliberate scope choice, not a gap.
- Nothing in Mindlore currently claims the iOS shake-to-undo gesture or three-finger-swipe, so no conflict to check.

## Modality (sheets, full-screen presentations)

Concrete rules:
- Use modal presentation only when there's a clear benefit (focus, decision, distinct task), it interrupts and needs an explicit dismiss.
- Keep modal tasks simple, short, and single-path; don't build a nested "app within an app" inside a modal, and don't include a button that could be mistaken for the modal's own dismiss control.
- Full-screen modal style suits in-depth content or multistep tasks (photo/video, editing).
- Always give an obvious, platform-conventional dismiss (top toolbar button or swipe-down on iOS).
- If dismissing a modal would lose unsaved content, confirm before closing (e.g., an action sheet offering Save).
- Title the modal so people know what task they're in.
- Never stack multiple modals visibly at once; let one close before presenting the next. Never show two alerts simultaneously.

For Mindlore:
- EntryInsightsView is explicitly a sheet over the editor rather than a push "because the editor's onDisappear runs its close rules", this is already modality used correctly (a distinct, short task).
- Page ordering, Add a name, AI Settings sheets, and the recorder's "ready" cover all appear to be single-purpose short modals with clear dismissal, matching the guidance; worth confirming none of them nests a further full navigation stack that could feel like an app-within-an-app (the entity page pushed inside its own NavigationStack from MindView/EntryInsightsView chips is the one case CLAUDE.md flags as needing its own `entityRouteReplacer`, which is a related but distinct concern from this modality rule).

## Settings

Concrete rules:
- Provide good defaults so most people never need to touch settings; minimize the number of settings offered (more settings = harder to find the one that matters, and feels less approachable).
- Don't duplicate systemwide settings inside the app (accessibility accommodations, authentication), implies those choices might not carry over.
- General/infrequently-changed settings belong in the app's own settings area; task-specific options (filters, sort order, show/hide parts of the current view) belong inline on the screen they affect, not buried in a separate settings screen.
- Only add to the system Settings app for truly rarely-changed items, and provide a button in-app to jump directly there.
- Detect what you can automatically (dark mode, connected accessories) rather than asking.

For Mindlore:
- The five-row Settings redesign (General/AI/Your journal/Today and reminders/About) is already a minimization move away from an eight-section Form; the CLAUDE.md explicitly calls out internal-state keys that deliberately get *no* UI control (aiEnabledAt, lifeAreaNames, etc.), this matches "minimize settings" well.
- Life areas and "how you're written about" living under Your journal rather than AI (because they work with AI off) is consistent with "put things where their effect actually shows up," a good example of the task-specific-vs-general split.
- Double check: window/kind filters on Mind (People/Places/Projects/Themes chips) and journal chips (Notes/Creative) already live inline on their own screens, not in Settings, matches "task-specific options stay with the task."

## Managing notifications / Notifications

Concrete rules:
- Consent required before sending any notification; people can always mute all in system settings (except gov't alerts).
- Four interruption levels: Passive, Active (default), Time Sensitive (needs entitlement-adjacent restraint: reserve for things relevant *right now or within the hour*; a first-use system explainer lets people opt out of it specifically), Critical (rare, health/safety, needs an entitlement, can override Ring/Silent).
- Never use Time Sensitive for marketing; never send marketing/promotional notifications without separate explicit opt-in, and give an in-app settings screen to change that choice later.
- Content rules: concise, at-a-glance; don't send multiple notifications about the same thing; don't tell people to "do X in the app" (either give a real notification action or say nothing); use an alert (not a notification) for error messages; never put sensitive/personal/confidential info in a notification body (anyone could glance at a locked screen); if the app is foregrounded when a notification event happens, show the info unobtrusively in-context rather than firing an actual notification.
- Title: short, title case, no ending punctuation; if you can't give a meaningful title, let the system show the app name instead of a generic "New Document" placeholder.
- Body: full sentences, sentence case, real punctuation, no truncation tricks.
- Write "hidden preview" placeholder body text for when people disable previews (e.g., "Reminder," not blank), sentence-style caps.
- Badges: only ever represent unread-notification count; never repurpose for unrelated numeric info (scores, prices); update immediately when read so it never lies; never fake a badge visually if the person disabled real badges.

For Mindlore:
- `DailyReminder` is exactly one local notification a day, off by default, "fixed neutral words, no badge" per CLAUDE.md, this already satisfies "don't send marketing/promotional notifications" and the anti-spam "one notification for one thing" rule, and avoiding sensitive content in the body (a journaling reminder saying nothing about entry content) directly satisfies "no sensitive info in a notification."
- Since it's a single daily local reminder with no marketing use, Passive or Active interruption level is appropriate; Time Sensitive/Critical would clearly be misuse here and nothing suggests Mindlore claims either, worth a one-line confirmation in code that the notification's interruption level isn't set to Time Sensitive or above.

## iCloud

Concrete rules:
- Aim for transparency: people shouldn't need to think about where content "lives," just trust it's current everywhere.
- Avoid making people choose per-document what syncs; sync everything automatically when possible.
- Balance freshness vs. bandwidth/storage: for very large documents, let people control when content downloads, and show subtle feedback if a download takes more than a few seconds.
- Be conservative with iCloud storage (it's a paid, finite resource for the person), don't put regenerable app resources in the Documents folder that gets backed up.
- Handle iCloud-unavailable gracefully; no alert needed for a deliberate iCloud-off/Airplane Mode state, but do unobtrusively note that changes won't sync elsewhere yet.
- You *can* store app state/settings in iCloud too (not just documents), but only settings people would want mirrored to every device (not "more useful at work than home" settings).
- Warn and confirm before deleting a document that syncs via iCloud, since deletion removes it everywhere, not just locally.
- Resolve sync conflicts automatically when possible; if not, surface an unobtrusive, easy-to-resolve prompt, as early as possible so nobody works in the "losing" copy for long.
- Include iCloud-synced content in search results.

For Mindlore:
- The app already deletes without an "are you sure" (UndoQueue's 5-second grace instead), this is a deliberate divergence from "warn before deleting a synced document," presumably an accepted tradeoff given the app's overall philosophy of undo-over-confirm; worth flagging explicitly as a considered exception rather than an oversight, since it's a spot where HIG's default recommendation differs.
- `SyncStatusMonitor`/`SyncStatus`'s sentences in Settings > General match "unobtrusively let people know changes aren't syncing yet" well, rather than a blocking alert when iCloud is off or the account changed.
- `SyncDuplicates`'s automatic, no-prompt merge-on-sync-settle for entities/recaps/insights is a strong implementation of "resolve conflicts automatically when possible, without dialogs", good alignment, no gap.

## Managing accounts

Concrete rules:
- Only require an account if core functionality truly needs one; otherwise let people use the app account-free. If required, explain the benefit right in the sign-in view, and delay sign-in as late as possible (let people explore first).
- Prefer Sign in with Apple, or at minimum passkeys over passwords; if passwords are unavoidable, require two-factor.
- Name the exact authentication method in button labels ("Sign In with Face ID," not generic "Sign In"), and only reference methods actually available on the current device.
- Don't add an app-specific toggle for biometric auth, that's a system-level setting already, redundant and confusing to duplicate.
- Don't call it a "passcode" for in-app auth (people will think you mean their device passcode).
- Account deletion: must be a real deletion, not just deactivation; must be reachable in-app (or a direct, undisguised link to a web page that does it, not buried in a Privacy Policy); as consistent whether done in-app or on web; can offer scheduled-for-later deletion but must also offer immediate deletion; tell people when deletion will complete and confirm when it's done; if the app used Sign in with Apple, revoke its tokens on deletion; clarify how any subscription billing/cancellation interacts with account deletion (Apple continues billing subscriptions until canceled, independent of account deletion).

For Mindlore:
- Mindlore has no accounts at all, journaling is local-first with iCloud as transparent sync, not an app account, so this whole HIG page is essentially moot; the one point worth carrying over is Face ID: `AppLock`'s Face ID lock should already avoid adding a redundant "enable biometrics" in-app toggle beyond turning the lock feature itself on, and any lock-related copy should name "Face ID" specifically rather than a generic "Unlock" label, consistent with "name the actual authentication method."
- No sign-in, no account deletion flow, no subscription-cancellation-on-delete concern applies today, since there's no in-app account or subscription described in the CLAUDE.md AI/Settings sections. Flag as not applicable rather than a gap.
