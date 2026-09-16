# Mindlore: what's left

Kept up to date as work lands. The finished plan for the AI providers PR, with its decisions and
review history, is archived in `tasks/archive/ai-providers.md`; the v1 capture-and-storage plan is in
`tasks/archive/v1-capture-storage.md`.

## Device smoke test, session 2

Session 1 (2026-09-15, iPhone 17 Pro) covered the upgrade over real entries, key setup, cloud
transcription, the airplane-mode fallback, three real handwritten pages, the date read off a page,
approval gating insights, cleanup on page text, editing moods, page previews, and whole-entry
scrolling. What it found was fixed the same evening.

These steps are still unrun. `tasks/smoke-test.md` has the expected events for each.

- [ ] **Bad key.** Settings, AI, replace the key with `sk-not-a-real-key`, record 10 seconds. Expect
      `ai.error` with `ai.invalidKey`, a fallback to the phone, and no re-upload after a relaunch.
      Restore the real key afterwards.
- [ ] **Pages offline.** Airplane mode on, photograph one page, confirm. Expect one `ai.offline` and
      no repeats, then the transcription finishing on its own when airplane mode goes off with the app
      still open. This is the check for the network-resume fix.
- [ ] **Edit pages and restart.** Remove a page from a transcribed photo entry and confirm the
      warning. Expect `pages.restarted`, a fresh transcription, and review again.
- [ ] **Typing over a transcription in flight.** The typed text wins, and "Replace with page
      transcription" brings the page text back for review.
- [ ] **Force-quit during insights.** Tap Done and swipe the app away. The run finishes after
      relaunch, with one attempt counted and one `insights.completed`.
- [ ] **Lock the phone.** Lock for a minute, unlock, record. Cloud transcription still works, which
      means the key is readable after first unlock.
- [ ] **Optional: a 25-minute recording**, to watch chunked uploads on a device.
- [ ] **Optional: five pages in one entry**, for memory and stored size at a realistic maximum.

## Deferred from the pre-merge code review (2026-09-15)

Taken before merge: main-actor network/audio/image work moved off with `@concurrent`; a cancelled
request now rolls back instead of ending a job; the text view is safe during keyboard composition; the
editor's close rules no longer fire when a cover opens over it; titles and insights pause while offline
and have a Run AI path; a held title stays pending until applied; UI test keys never reach the Keychain;
insights input is capped; the key check is cached; dismissing a cleanup no longer discards it.

Left for later, each with its reason:

- [ ] **Voice chunks aren't saved as they finish.** A failure on chunk 9 of 10 re-uploads all nine next
      time, up to the 3-attempt cap. Pages already save per page; voice should do the same. Costs money
      only on long recordings that fail mid-way.
- [ ] **`retryAfter` from a 429 is parsed and ignored.** The next attempt waits for a scene change or
      launch rather than the time the provider asked for.
- [ ] **A Keychain error reads as "no key".** `ProviderAccountStore` swallows the status, so a locked or
      broken keychain looks like an unconfigured account instead of an error worth showing.
- [ ] **Cancelling "Edit pages" discards pages added during that edit** without asking. Pages already on
      the entry are untouched.
- [ ] **Diff and thumbnail work happens in view bodies** (`CleanupReviewView`, `PageStripView`,
      `PageOrderView`): fine at today's sizes, worth caching if entries or page counts grow.
- [ ] **Turning every insight section off** lets Run AI send a request with an empty schema, which the
      provider rejects. Should be blocked in the UI.
- [ ] **Test harness fakes hang rather than fail** when a coordinator stops calling them; the unit test
      command's per-test time allowance is what stops a full stall.

## Known limits

- Memory and storage above five pages per entry are unverified on a device; the 20-page cap is a guard.
- A force-quit inside the document camera loses that scan: VisionKit only hands pages back on Save.
- An upload that is still running when the app is backgrounded may be suspended; it retries later.
- Privacy wording in the app, and the `PrivacyInfo.xcprivacy` data collection declarations, still need
  their own review before any external build.

## Next projects

1. **iCloud sync.** Planned in `tasks/archive/v1-capture-storage.md`, blocked on the paid Apple
   Developer Program. Includes the entry safety copy, recovery, and the cross-device transcription rule.
2. **The knowledge graph.** Turn the tags and mentions already stored on every entry into entities with
   user-written bios, resolve "Sarah" and "my sister" to one person, and feed that back into analysis.
   This is the product's actual differentiator (`docs/mindlore-build-plan.md`, Phase 2).
3. **Synthesis.** Daily, weekly, and monthly summaries, mood trends over time, and search.
4. **Import and visualization.** Text import, backfilling old journals, then the graph view.
