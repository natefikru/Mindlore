# Privacy review before the first external build

`docs/remaining-work.md` flagged this: "the in-app privacy wording and the `PrivacyInfo.xcprivacy`
data collection declarations need their own review before any build goes to anyone else." Done
2026-09-29, against `main` at the polish/phase-3 merge. Three things were checked: what the app
tells the user, what the manifest declares, and what App Store Connect's own privacy questionnaire
will ask for, which lives outside the repo and nothing here can set.

## In-app wording: read for accuracy, not just tone

Every place the app makes a privacy claim, checked against what actually happens on that path.

- **`AIConsent.swift`** ("Send your journal to OpenAI?"): names OpenAI, says recordings, page
  photos, and entry text go to it using the user's own key, and that a Chat question sends the
  entries it needs. Accurate, and it is the one gate every OpenAI path checks (`aiEnabled`).
- **`OnboardingWelcomePage`** (formerly `WelcomeView`'s body, now onboarding's page one): "Private
  unless you say so" is conditioned correctly, on-device or not, and never claims data "never
  leaves your phone" unconditionally.
- **`WelcomeSyncLine`**: the iCloud line the same screen shows is dynamic on real sync status, says
  "Never on a server of ours" only in the state where that's true (`.upToDate`/`.paused`, mirrored
  through the user's own iCloud), and tells a signed-out user to sign in rather than implying sync
  is already running.
- **Settings' AI screen footer**: "When AI is on, recordings, journal pages, and entry text are
  sent to OpenAI for transcription, titles, and insights. Opening a person, place, or project in
  your journal sends the sentences that mention it, to draft a short description." Matches
  `AIServices`' actual behavior (bios go through the same OpenAI path, gated the same way).
- **`SyncSettingsSection`**: shows `SyncStatus.summary`/`.explanation`, both computed from the
  live `SyncStatusMonitor`, never a static claim that could drift from reality.

No false or overstated claim found anywhere in this pass. The one gap worth naming: before this
change, the privacy row (AI boundary) and the iCloud row (sync boundary) lived on the same screen
but never cross-referenced each other, so a fast reader could walk away thinking "private" covers
sync too. Folding both into onboarding's page one (this PR) doesn't fix that by itself, but it's
the same screen it always was; a future pass could combine the two rows into one sentence that
names both boundaries. Not done here, since it's a copy change with no accuracy problem behind it,
and copy changes are the owner's call.

## `PrivacyInfo.xcprivacy`

Unchanged: `NSPrivacyTracking = false`, empty `NSPrivacyTrackingDomains`, empty
`NSPrivacyCollectedDataTypes`, and the two required-reason API entries (`CA92.1` for UserDefaults,
`C617.1` for file timestamps) `CLAUDE.md` already documents.

The empty `NSPrivacyCollectedDataTypes` is correct as it stands. That dictionary declares data
*the app or an SDK it bundles* collects and sends off-device on Apple's own initiative or an SDK's;
Mindlore bundles no analytics or ad SDK, and the OpenAI calls are the user's own request, over
their own account, to a server the user chose to add a key for. That is a user-initiated network
call the app makes, not "collection" in the manifest's sense, the same way a browser's manifest
doesn't declare every page a person visits. Nothing here needs to change for the onboarding PR, and nothing else in the codebase writes to a
third-party endpoint outside the AI layer (checked every literal `https://` host in `Mindlore/`:
`api.openai.com` and `platform.openai.com` for the AI layer, and `findahelpline.com`, a crisis
link `LifeConcernView` shows and never fetches, not a network call the app itself makes).

Revisit this only if a future build adds a bundled SDK (crash reporting, analytics, an ad network)
or starts sending anything the user didn't ask to send.

## App Store Connect's App Privacy questionnaire (not in this repo)

This is the separate form under App Store Connect, My Apps, Mindlore, App Privacy, filled in by
hand before submission. It asks what data types are collected and why, independent of the
manifest above. Based on what the app actually does today:

- **Data collected: none required.** Mindlore's own servers collect nothing; there is no Mindlore
  account, no analytics, no crash reporting. The honest answer to "Do you or your third-party
  partners collect data from this app?" is **No** for Mindlore's own collection.
- **The OpenAI question is where judgment is needed.** Apple's guidance treats data the user
  explicitly sends to a third party they chose, using credentials they provided, as still worth
  disclosing if it's collected *through* the app. The safer answer, and the one that matches how
  Rosebud, Day One, and other AI-journal apps answer this today: declare **Audio Data** and
  **Other User Content** (the journal text and page photos), both **Used for App Functionality**
  only, **Not linked to identity** (OpenAI gets the content and the user's own API key, never a
  Mindlore account or Apple ID), **Not used for tracking**. This only applies when AI is on; the
  honest framing in the submission notes is that this collection is optional, off by default, and
  gated by the in-app consent alert (`AIConsent`) before it can happen at all.
- **iCloud sync is Apple's own service**, not a third party Mindlore integrates, and App Store
  Connect's privacy label doesn't ask about it separately; nothing to declare there beyond what's
  already covered by "the developer's own service" exemptions Apple documents for CloudKit.
- **Write the review notes to say this explicitly**, alongside the existing guidance in
  `docs/remaining-work.md`'s TestFlight section (AI is optional, uses the user's own OpenAI key, a
  reviewer needs a key to try it): add a line that the only data ever collected is what the user
  explicitly opts into sending to their own OpenAI account, gated by an explicit in-app consent
  alert, and that Mindlore's own servers collect nothing.

None of this needs a code change. It's a checklist for the App Store Connect form, kept here so the
answers are decided once, deliberately, rather than guessed at submission time.
