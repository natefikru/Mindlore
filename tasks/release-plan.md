# Release plan

Written 2026-09-22 from three passes: a competitor study (Mindsera, Rosebud, Everkind), an inventory of documented and undocumented remaining work, and a UI/UX audit of every view plus simulator screenshots of the empty and story journals. Nothing here is started. The decisions at the bottom come first.

## The decision that shapes everything: AI without a key

Insights only run with an OpenAI key the user brings (`AIServices.automaticInsightsUsable`, `AIServices.swift:101`). Insights feed names, moods, areas, loose ends, the Mind map, Today's cards, and Reflect. So a normal App Store user, who has never seen an OpenAI dashboard, gets a good local voice journal and four surfaces that stay empty forever. An App Store reviewer gets the same thing and may call the app broken.

Three ways out:

1. **On-device insights through Foundation Models (recommended for 1.0).** Titles already run on the phone. Insights per entry are small, structured, and fit `@Generable` guided generation. The on-device model will name fewer things and name them worse, but every surface fills in with no key, no account, no cost, and nothing leaving the phone, which is also the best privacy story in this category. The OpenAI key stays as the "better results" option. Ask already falls back on-device the same way. Needs an Apple Intelligence device; older phones get the plain journal and a line saying why.
2. **Hosted AI behind a subscription.** What all three competitors do ($65 to $130 a year). Needs a server, a proxy for the key, StoreKit, a privacy policy that covers the server, and running costs. Far more work, and it makes Mindlore a service.
3. **Bring-your-own-key only.** Ships as is, and ships to a niche. Review notes must explain it.

Option 1 also answers pricing: a free or one-time-purchase app with no running costs. A subscription can come later with option 2.

## What the competitors teach

**The shared shape.** All three wrap the journal in a conversational AI that talks back after every entry, sell "it remembers you" as the premium feature, lean on therapy frameworks (CBT, ACT, IFS, Stoicism) while disclaiming that they are therapy, and keep capture free with the AI behind a paywall. Memory is the most praised and the most hated feature everywhere: when it works it is "better than the therapists I paid for", and when it breaks it reads as betrayal. Everkind's worst review is an AI that decided the user would "spiral" and refused to answer.

**Borrow.**

- **App lock.** Face ID or passcode on open. All three have it, and nobody writes a private journal into an app without it.
- **Export.** Markdown and JSON (and PDF if it's cheap). Only Mindsera has it. It's a trust signal ("my journal is not a prison"), and it's also Mindlore's only backup until sync exists.
- **A year view in Reflect.** Mindsera's Story View goes daily through yearly. Reflect stops at a month, and a year is where the counts get interesting.
- **Custom lenses already exist.** Mindsera's user-defined "Minds" are custom prompts, and Mindlore has those in Advanced. Nothing to add.

**Trash.**

- Follow-up questions after every entry (Rosebud, Everkind). This is the hand-holding loop itself.
- Mentor personas, framework menus, "thinking traps" labels. They claim clinical authority the app doesn't have.
- Generated meditations, daily wellness goals, habit nudges. Prescriptions.
- Tone questionnaires at onboarding. They set the AI up to perform a personality.
- Streaks. Nobody praised or complained about them in the reviews. The week strip already shows which days you wrote, and that's enough.

**Own.** None of the three shows its memory. They say it remembers and you have to trust them. Mindlore's memory is visible and correctable: the map, merge and unmerge, "Which one?", Ask's citations, and "What was sent". That is the positioning, **a memory you can see and fix**, and it's already built. The app-store copy should say so. Nobody else has App Intents or photographed paper pages as a real entry type either.

## Must before release

**Account and store**
- [x] Paid Apple Developer Program, bought 2026-09-22. Still to do: move the project from the Personal Team (`7DZBU56KUA`) to the paid team once Xcode lists it.
- [ ] Privacy policy URL and support URL (App Store Connect requires both).
- [ ] App Privacy answers in App Store Connect. `PrivacyInfo.xcprivacy` declares no collected data. That's defensible for on-device only, but entry text and audio go to OpenAI when the user adds a key. Decide how to declare that and keep the manifest and the label in agreement.
- [ ] Review notes: what works with no key, and a test key or a clear statement that AI is optional.
- [ ] Screenshots and description. `-seedStoryJournal` is the screenshot source.
- [ ] TestFlight build to a few people before submission.

**Product**
- [ ] AI without a key (decision above).
- [ ] First run (B3, never built). One screen, not a carousel: what Mindlore is, that it works offline, the microphone and speech prompt with a reason in front of it, and an optional AI setup. Plus the contextual empty states below.
- [x] App lock (Face ID, fallback to passcode), plus covering the app switcher snapshot.
- [x] Export (a folder of Markdown files, journal.json, recordings and page photos), and "Delete all data" in Settings.
- [x] iPad: set `TARGETED_DEVICE_FAMILY = 1` (iPhone only). It's currently `1,2` with no iPad layout.
- [x] Release build check. Release didn't compile at all (`DemoJournal` referenced outside `#if DEBUG` in `MindloreApp`), so the app couldn't have been archived. Fixed; seeds are Debug-only.

**Correctness** (from the known bugs list in `docs/remaining-work.md`)
- [x] A Keychain error is read as "no key". The user sees their key vanish.
- [x] Cancelling a page edit silently throws away newly added pages.
- [x] Voice chunks aren't saved as they finish, so a failure re-uploads the whole recording. Cost, not data loss, but it's the Rosebud complaint ("stuck mid-transcription").
- [ ] Device pass: the Phase A steps still open in `docs/remaining-work.md` §1, Reflect steps 33 to 36, and a fresh-install pass on a wiped phone (or a second device).

## Low-hanging UX fixes (one PR)

From the audit, each small, ranked by how much it helps.

1. Mind's empty state (`MindView.swift:194`) and the search panel (`SearchPanel.swift:220`) never say names come from AI. With AI off, say so and link to Settings, the way the insights sheet does at `EntryInsightsView.swift:184`.
2. Ask shows suggestion cards on an empty journal with no key (`AskView.swift:230`), and you only find out it can't answer after sending. With no entries, show one line instead. When Ask is unavailable, say so before a send.
3. Journal's empty state talks about "the microphone or the pencil", which are unlabeled glyphs (`EntryListView.swift:73`). Give it Record and Write buttons.
4. Four haptics are defined and never fired: `recordStart`, `recordStop`, `failed`, `detent` (`Haptics.swift`). Starting and stopping a recording is silent.
5. Swipe-to-delete an entry, delete a conversation, and remove the key all act with no confirmation (`EntryListView.swift:63`, `AskHistoryView.swift:29`, `AISettingsView.swift:69`, entity unlinks at `EntityView.swift:320,359`). Pick either confirm or undo as the one policy and apply it everywhere.
6. The editor toolbar can show five trailing icons (`EntryEditorView.swift:117`). Move Entry date and Edit pages into More.
7. Reflect stamps "All caught up." on empty weeks (`ReflectWeekSection.swift:44`). Say "No entries this week" instead.
8. The dismiss X on Today and Reflect rows is about a 12pt target in `.tertiary` (`TodayCards.swift:104`, `ReflectQueueRow.swift:22`). Make it 44pt and `.secondary`.
9. Sheet Done buttons sit leading on some sheets and trailing on others. Make them all trailing.
10. Typography: the play button uses a fixed `size: 34` (`AudioPlayerView.swift:31`), and serif shows up in app chrome in Ask, Mind, and Reflect titles, against the rule that serif is only for the user's own writing.

**Copy.** These lines lean toward coaching or read as slogans:

| Where | Now | Change to |
|---|---|---|
| `TodayCopy.swift:30` | It's been a while | Quiet lately |
| `TodayCopy.swift:80` | Fades today unless you write about it | Fades today |
| `AskPrompt.swift` | plain sentences, warm, specific | plain sentences, direct, specific |
| `MindView.swift:195` | Your map starts with a word | Nothing on the map yet |
| `SettingsView.swift:94` | Names you haven't written about | Resurface quiet names |
| `KeepCard.swift:196` | Noticing | Reading |
| `MindView.swift:234,246` | Colour by | Color by |

**Accessibility.**
- Today cards open with `onTapGesture` (`TodayCards.swift:112`), so VoiceOver can't activate them. Make them a `Button`.
- About eight animations and symbol effects skip `Motion.resolve`, so Reduce Motion doesn't stop them (`MindView.swift:85,253`, `SearchPanel.swift:116`, `AskView.swift:103,306`, `KeepCard.swift:82`, `AskTurnView.swift:107`, `ReflectMonthRow.swift:34`).
- Fixed heights clip at accessibility text sizes: `MindView.cardHeight` (200), the peek sheet detent (220), `SearchPanel.peekHeight` (76).
- The unwritten-day rings use `hairline` at 0.08 opacity and nearly disappear on Paper.

## Should

- [ ] Reflect needs a second door. It's reachable only through the week strip, which hides when Today is empty.
- [ ] Pause in the record accessory. Pause and Discard sit in a long-press menu nobody finds.
- [ ] Crash reporting through MetricKit. No third party, nothing leaves the phone that the user didn't send, and today a user's crash is invisible to you.
- [ ] Honor `retryAfter` on a 429.
- [ ] Remaining Phase B polish (B4 recording motion, B7 remainder, B9 final privacy pass).
- [ ] Year view in Reflect.
- [ ] Import from Day One and Markdown, so people can move their old journal in.

## After the paid account

- iCloud sync. The schema has been CloudKit-ready from day one, so this is mostly a switch plus testing. Until then, iOS device backups already carry the store, so a new phone restored from backup keeps the journal. Uninstalling still loses it, which is why export is on the must list.
- Widget and Live Activity (B8). App Groups need the paid team.
- Hosted AI and a subscription, if option 2 ever happens.

## Later

Embeddings for Ask (indirect-description recall is measured at 0.00), typed entity relationships, searching inside past Ask conversations, localization (the string-catalog settings are on, and there are no translations).

## Proposed order

1. **Decide** the four questions below.
2. **Hardening PR:** the three correctness bugs, iPad off, the release-build check.
3. **UX PR:** the ten fixes, the copy table, the accessibility items.
4. **Trust PR:** app lock, export, delete all data.
5. **On-device insights** (if option 1), then first run, which depends on what AI setup looks like.
6. **Device pass** over all of it, plus the owed steps.
7. **Store:** paid account, privacy policy, App Privacy answers, screenshots, TestFlight, submit.

## Decisions (owner, 2026-09-22)

1. AI without a key: **on-device insights** through Foundation Models, with the OpenAI key as the better-results option.
2. Price: **free**.
3. Destructive actions: **Undo pill**. Delete at once, with five seconds to take it back.
4. First up: **the hardening PR and the UX PR**.
5. "Let it go" stays for now.
