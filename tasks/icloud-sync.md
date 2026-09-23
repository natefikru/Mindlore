# iCloud sync

Branch: `feature/paid-team`, from `main` at `ead7a53`. Status: revision 2 (a sub-agent review folded in),
awaiting the owner's approval. Nothing below is built.

The v1 plan designed sync in 2026-09 when the journal held one model (`Entry`) and deferred it to a
Phase 6 behind the paid program (`tasks/archive/v1-capture-storage.md`, "Phase 6"). The program is
active as of 2026-09-23 and the team ID did not change (`7DZBU56KUA`, now a paid Individual team),
so nothing in the project's signing settings moves. The schema grew to nine models since, and
several of them are written by launch sweeps and AI jobs that would now run on two phones at once.
This revision keeps every v1 decision and adds what the new models need.

## Decisions carried from v1

- **CloudKit always on when signed in, the account only drives the UI.** A phone with no iCloud
  account keeps a fully working local store.
- **A local safety copy of every entry**, outside the CloudKit store, because Apple's mirroring
  purges the local store on sign-out, on turning iCloud off for the app, and on a false
  access-revoked signal, and anything not yet uploaded is gone.
- **Only the device that made an entry transcribes it.** v1 said this for recordings; see
  "AI runs where the entry was made" for why it now covers every automatic AI job.
- **Settings mirror through `NSUbiquitousKeyValueStore`**, missing keys meaning "default", so a
  fresh phone never pushes its defaults over the real ones.
- The container is `iCloud.com.natefikru.mindlore`. It is permanent once created.

## Owner requests

- **Sync lives at the top of Settings** (owner, 2026-09-23). A new first section, above "Your
  journal".

## What changes

### 1. Capability and container

- Add `Mindlore/Mindlore.entitlements` with `com.apple.developer.icloud-container-identifiers`
  (`iCloud.com.natefikru.mindlore`), `com.apple.developer.icloud-services` (`CloudKit`),
  `com.apple.developer.ubiquity-kvstore-identifier`, and `aps-environment`. Set
  `CODE_SIGN_ENTITLEMENTS` on the app target's Debug and Release configurations only.
  `UIBackgroundModes` already carries `remote-notification`.
- Let Xcode register the container and refresh the development profile (`deploy.sh` already
  passes `-allowProvisioningUpdates`).
- Regenerate the App Store profile in the developer portal so it carries iCloud, then rerun
  `scripts/release/set-secrets.sh`. Until that happens every TestFlight upload fails at archive.
- **Risk to settle first:** the CI simulator build signs with no account. Simulator builds sign
  "to run locally" and should embed the entitlements without a profile, but that is unverified for
  iCloud. Phase 1 pushes the entitlements alone and watches CI before anything else lands.

### 2. The store

- `AppConfig.cloudKitContainerID = "iCloud.com.natefikru.mindlore"`.
- `ModelContainerFactory.make` already gives only `.default` a `.private` database; `.inMemory`
  (unit tests), `.file` (UI tests, `-seedStoryJournal`, `-seedDemoJournal`) stay `.none`, so no test
  run and no demo journal ever touches iCloud. A test asserts it, since the entitlement's presence
  would make an `.automatic` configuration sync without anyone asking.
- `CloudKitSchemaRulesTests` gains the remaining CloudKit rules: every relationship has an inverse,
  no `.deny` delete rule. `CloudKitSchemaTests` loads a `.private` configuration at a temp URL and
  asserts it opens, enabled only when the running binary carries the entitlement.
- **A sync switch.** "Sync with iCloud", on by default, stored device-locally (never in the synced
  key-value store, or turning it off on one phone would turn it off on all). Mirroring can't be
  toggled on a live container, so the switch rebuilds the container and `RootView` under it, the
  same shape the app already uses when a demo store is opened. Turning it off keeps the local
  store as it is; turning it back on exports what is there. This is bigger than it reads:
  `MindloreApp` holds the container as a `let` set in `init`, and `RootView.init` captures its
  main context, so the switch needs the app to hold the container as state and key the root on
  it. It gets its own phase (2b) and can be cut to "takes effect at next launch" if the rebuild
  fights the coordinators' lifetimes.

### 3. Status, at the top of Settings

- `Mindlore/Sync/SyncStatusMonitor.swift`, `@Observable`: `.syncing(lastEvent: Date?)`,
  `.deviceOnly(reason)`, `.checking`, `.off`. Account status via an injected lookup, refreshed at
  launch and on `.CKAccountChanged`; activity from `NSPersistentCloudKitContainer.eventChangedNotification`
  (SwiftData's mirroring posts the Core Data events) for "last synced" and for surfacing
  `quotaExceeded`, `notAuthenticated`, and a partial failure as words, never raw error text.
- `SyncSettingsSection` is the first section in `SettingsView`: the switch, one status line
  ("Up to date", "Syncing", "On this iPhone only: sign in to iCloud to sync", "Paused: your iCloud
  storage is full"), and "Restore missing entries" when the recovery check has found some. The
  privacy footer's "stored on this device" wording switches to "stored on this device and in your
  private iCloud" while syncing.
- Diagnostics: `sync.status`, `sync.event` (kind, success, duration, error code), counts only.

### 4. AI runs where the entry was made

Two phones launching against the same synced journal would each run the launch sweep, each
transcribe the same `awaitingText` recording, and each run insights on the same entry, producing
duplicate loose ends, duplicate entities, and double the OpenAI spend.

- A device-local `LocalOrigin` set (UserDefaults, never synced) of entry ids this phone created or
  ingested. `Entry` gains nothing: the id set is the whole mechanism.
- `TranscriptionCoordinator`, `AIPassTrigger`'s launch sweep, and the title and insights
  coordinators' automatic paths skip an entry not in the set. The manual buttons (Transcribe here,
  Generate insights, Retry) work anywhere and add the entry to the set.
- An entry from another phone still waiting for text shows "Waiting for text from your other
  device" with "Transcribe here", as v1 planned. Typing still works and clears `awaitingText`.
- Entries that exist before sync is first switched on are all added to the set once, so the phone
  that had the journal keeps running its jobs.

### 5. Duplicates two phones can still make

Mirroring has no uniqueness, so rows that mean the same thing can arrive twice. Each gets a
deterministic merge, run after a remote change lands (`.NSPersistentStoreRemoteChange`, debounced)
and at launch, winners chosen by `createdAt` then `id` so both phones pick the same one:

- `Entity`: same normalized `key` and kind, neither merged nor hidden-by-user-difference, merged
  through `GraphEditor.merge` so aliases and links move and `mergedIntoID` keeps old ids resolving.
  Only entities neither phone has touched by hand are auto-merged; the rest go to Mind's review
  question as "Same person?", which already exists.
- `ReflectSummary`: same period and kind, keep the newest.
- `EntryInsights`: two rows pointing at one entry (possible if both phones ran insights before
  gating, or during the window between phases), keep the newest `generatedAt`, delete the other,
  so `entry.insights` never picks one at random.
- `AskMessage`: a conversation continued offline on two phones can hand out the same `index`
  twice. Order by `index` then `createdAt` so nothing is lost, and renumber on the next append.
- `EntityLink`: same `entityID`, `entryID`, and source, delete the extras.
- `LooseEnd` is protected by rule 4 rather than a merge, since only the origin phone writes them
  automatically, and a user-made one is theirs.

Launch sweeps (`EntryDateRepair`, `LooseEnd.fade`, `GraphIndexer.sweep`) should write the same
values on both phones from the same inputs. A test runs each twice over one store and asserts the
second pass changes nothing, but that only proves idempotence; two phones sweeping stale copies
seconds apart is a smoke step, not a unit test.

`contentRevision` guards a job against an edit on the same phone. It says nothing about another
phone: a synced edit can land with a lower revision and win on last-writer. `LocalOrigin` is what
keeps two phones' jobs apart, and the plan relies on it alone for that.

### 6. Settings mirroring

`SettingsStore` reads through `KeyValueStore`; a `MirroredKeyValueStore` writes both
`UserDefaults` and `NSUbiquitousKeyValueStore` for an allow-list and applies incoming changes
(`didChangeExternallyNotification`) to the local copy. The allow-list is the journal's own shape:
`lifeAreaNames`, `hiddenLifeAreas`, `userName`, `journalVoice`, the journal font, insight section
toggles, `customInsightPrompts`, `resurfacingEnabled`. Never mirrored: the API key (Keychain,
`kSecAttrSynchronizable = false`, on purpose), `providerAccounts` and every key that points into
it or picks a provider (`speechEngine`, `speechAccountID`, `pageAccountID`, `textAccountID`,
`titleGenerator`, `insightsGenerator`, `askGenerator`, `askGeneratorChosenByUser`), since an
account id without its key on the other phone is worse than no setting, `aiEnabled`/`aiEnabledAt`
(whether this phone sends anything to OpenAI is the phone's decision), `appLockEnabled`, the
reminder, `todayDismissed`, `welcomeSeen`, the sync switch itself.

### 7. Safety copy and recovery

As v1 designed: every save of an entry with text writes a JSON snapshot (id, dates, title, text,
kind, source; no audio, no page images) to `Application Support/EntryBackups/`, excluded from
iCloud backup like `Recordings/`. `SyncStatusMonitor` keeps an account fingerprint (a hash of the
status and the opaque user record name, never a name or email) and sets `pendingRecoveryCheck` when
it changes from a previously signed-in account. `EntryRecovery.missingEntries(backups:storeIDs:)`
then offers a banner with Restore all, Review, and Not now; a restore keeps the original `id`, so a
later sync can't duplicate it. Snapshots of deleted entries are removed by the delete path, or a
restore would resurrect them.

### 8. TestFlight and production

TestFlight builds talk to the CloudKit **production** environment. Before the first TestFlight
build with sync, deploy the schema to production in CloudKit Console; after any later model
change, deploy again before that build ships, or those fields silently never sync. Add this to the
release checklist in `docs/remaining-work.md` and as a comment in `release.yml`.

## Phases (one PR, each phase pushed and green before the next)

1. Entitlements file, `CODE_SIGN_ENTITLEMENTS`, schema rule tests, the `.none`-for-tests test.
   Container ID still nil. Proves CI and the phone still build and sign.
2. Container ID set, `SyncStatusMonitor`, the Settings section at the top.
2b. The sync switch and the container rebuild.
3. `LocalOrigin` and the AI gating, with the "other device" banner.
4. Duplicate merges and the twice-run sweep tests.
5. Settings mirroring.
6. Safety copy, recovery banner.
7. Docs: `CLAUDE.md` (the "signs with a free Personal Team" paragraph goes), `docs/remaining-work.md`,
   `docs/privacy-coverage.md` for the new events, the smoke steps.

## Tests

Unit: schema rules, `.none` for every non-default location, `SyncStatusMonitor` states from an
injected account lookup and fake events, `LocalOrigin` gating in each coordinator (a synced entry
not in the set is skipped; a manual run adds it), each dedupe with a fixed winner, sweeps
idempotent over one store, `MirroredKeyValueStore` allow-list and external-change handling,
`EntryRecovery` finding and restoring by id, the delete path removing a snapshot. A UI test for
the Settings section being first and showing "On this iPhone only" in the simulator, which has no
iCloud account. Nothing about CloudKit itself can be tested off a device.

## Phone smoke steps (the real test)

Two devices on one Apple Account are needed for most of these; an iPad works as the second.

1. Existing journal on the phone, update to the sync build: every entry, photo, and recording
   appears on the second device.
2. Write on one, edit on the other: both edits arrive, the last one wins.
3. Record on phone A: phone B shows "Waiting for text from your other device" and does not
   transcribe; A's text arrives on B.
4. **Gate** (v1): a device with no iCloud account works fully and Settings says device only; sign
   in, and entries made while signed out upload. If not, stop and re-plan.
5. **Gate** (v1): airplane mode, three entries, sign out of iCloud, relaunch: the banner appears,
   restore brings back all three, signing back in makes no duplicates.
6. The same new name written on both phones offline, then both online: one entity on the map.
7. Life area renamed on one phone shows on the other; the API key does not.
8. Sync switch off on B: B keeps its journal and stops receiving; back on: it catches up.

## Not in scope

- Sharing a journal with another person (`CKShare`), or a shared database.
- Syncing the API key or AI account settings.
- Syncing an in-progress recording or anything in `Recordings/`.
- Conflict UI beyond last-writer-wins on a field; two phones editing one entry's text at the same
  second keep the later save.
- A paid tier, and B8 (Live Activity, widget), which are separate plans.
- The Mac app.

## Questions for the owner

1. Sync switch on by default for someone signed in to iCloud? (Recommended: yes.)
2. AI only on the phone that made the entry, with manual buttons anywhere? (Recommended: yes; the
   alternative is two OpenAI bills and duplicate loose ends.)
3. Is the settings allow-list in section 6 right, in particular keeping "Use AI" per phone?
