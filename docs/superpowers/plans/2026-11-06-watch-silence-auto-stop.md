# Watch Silence Auto-stop Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task-by-task. Implement each behavior as a vertical test-driven slice through an agreed public seam.

**Status:** Proposed solution; implementation has not started. The user confirmed the 3-second default. Other recommendations below remain proposals for review.

**Goal:** After someone speaks into their Apple Watch, automatically stop the Recording Session, save a Note, and start its normal Workflow after a configurable period of silence.

**Architecture:** Reuse the Watch microphone's existing metering and implement the decision in `RecordingService`. Configure it through iPhone Settings → Apple Watch, persist the settings locally, and synchronize only the Watch recording preferences over the durable peer protocol. Reuse normal finalization and `WhimService.handleFinalized` for Delivery and Audio Synchronization.

**Tech Stack:** Swift 6, WhimCore, SwiftUI, AVAudioRecorder metering, UserDefaults, existing SQLite connectivity journal, Watch Connectivity, XCTest, Maestro.

**Spec:** [Issue #50](https://github.com/kumibrr/whim/issues/50), the user's settings/default/range requirements, `CONTEXT.md`, and `docs/superpowers/specs/2026-09-04-whim-v1-design.md`. This plan proposes extending the v1 rule that Watch capture continues until Stop, interruption, or the five-minute limit.

## Global Constraints

- Minimum iPhone version: iOS 18.
- Minimum Watch version: watchOS 11.
- The maximum duration is five minutes and is defined in one internal configuration location.
- Stop saves and sends; Discard immediately destroys the current Recording Session without confirmation.
- Watch itself does not perform transcription in v1.
- Preserve local recoverability, existing Receipt precedence, and server idempotency by Note ID.
- Test through WhimCore, platform adapters, the cross-device protocol, native presentation, and installed-app interfaces. Mock system boundaries and compose real owned modules in integration tests.
- Keep root `test:unit`, `test:integration`, and `test:e2e` runnable. Run `test:all` before declaring implementation complete.

## Proposed user behavior

User requirements:

- Controls live in the iPhone app under **Settings → Apple Watch**.
- **Auto-stop after silence** is enabled by default, including upgrades with no saved value.
- **Silence duration** is a slider from **2 seconds to 10 seconds**. The user confirmed a **3-second default**.

Recommended details:

- Use 1-second slider steps. Show the selected duration as “3 seconds”; label endpoints “2 s” and “10 s”. VoiceOver exposes an adjustable value with units.
- Keep the slider visible but disabled while auto-stop is off, preserving its previous value.
- Place the controls above the existing complication guide and synchronization information. Add `.watch` to the existing editable settings sections and use its existing Save action. Leaving without saving leaves the stored settings unchanged.
- Explain: “After you speak, Whim stops, saves, and sends when it detects silence. Applies to Apple Watch recordings.”
- Settings remain editable without a paired/reachable Watch. Save locally immediately; synchronize when possible. Show a pending state until the Watch confirms applying these preferences, independently of webhook synchronization.
- Apply to all Watch recording entry points. iPhone recording behavior stays as currently specified.
- Snapshot preferences at the start of each Recording Session. An incoming preference change applies to the next session; repeated Record continues to focus the current session.
- Require meaningful audio before arming silence auto-stop. Initial silence alone does not end capture. Retain the five-minute stop, manual Stop, and immediate Discard.
- Use a fixed internal minimum Recording Session duration of 2 seconds; expose only the enable toggle and silence-duration slider.
- Once armed, resumed audio resets the silence interval. Auto-stop follows normal completion, including existing visible/haptic feedback and normal queued/setup-required/failed states when Delivery cannot complete.

## Approaches

**Recommended: audio-level policy inside RecordingService.** The Watch already samples AVAudioRecorder peak power every 100 ms, and this service already owns maximum-duration stopping and finalization. This keeps behavior independent of view visibility and uses existing hardware boundaries. Metering estimates meaningful audio; it is not a semantic speech detector and needs physical tuning.

**Considered: timer in WatchModel or WatchRecorderView.** Small initial change, but couples a canonical recording rule to presentation lifecycle and can miss non-UI entry points. Does not fit wrist-down/background requirements.

**Considered: speech recognition or a dedicated voice-activity engine.** Could distinguish background noise better, but adds capture complexity, resource cost, and potentially new platform/permission constraints. Defer unless physical metering acceptance demonstrates a concrete need.

## Interfaces and file map

New focused owned code:

- `packages/WhimCore/Sources/WhimCore/Preferences/WatchRecordingPreferences.swift`: `WatchRecordingPreferences: Codable, Equatable, Sendable`, with `autoStopEnabled: Bool`, `silenceDurationSeconds: Int`, `.default == (true, 3)`, and validation requiring `2...10`.
- `packages/WhimCore/Sources/WhimCore/Recording/SilenceAutoStopPolicy.swift`: internal state machine owned by RecordingService; no separate public test seam.
- New companion `Preferences/WatchRecordingPreferences.test.swift` for Codable/domain validation and `Preferences/WatchRecordingPreferences.integration.test.swift` for actual preference-store migration and restart behavior.

Existing interfaces to extend:

- `AppComposition/WhimClient.swift`: add `PreferenceInput.watchRecording` and `watchRecordingRevision: UInt64`, defaulting to `.default` and `0` in existing initializers and when decoding absent legacy keys. The revision is synchronization metadata owned by WhimService, never an editable UI field. Preserve all other preference values on updates.
- `AppComposition/WhimService.swift`: validate and save preference changes; allocate the next revision only when Watch values change on iPhone; reconcile pending publication on launch/activation; load the local Watch preferences when starting Watch capture. Preference reads must remain local and must not await peer reachability or network work.
- `Recording/AudioRecorder.swift`: add `RecordingEvent.meter(elapsed: TimeInterval, peakPowerDBFS: Float)` so the policy consumes a level and its recording-relative timestamp from one sample.
- `Recording/AVAudioRecorderAdapter.swift`: emit that event from the existing 100-ms metering loop, preserving existing elapsed/waveform events. Do not add a second recorder, capture engine, or polling task.
- `Recording/RecordingService.swift`: extend `start(source:autoStop:)` with `autoStop: WatchRecordingPreferences? = nil`. Activate the policy only for `.appleWatch` with enabled settings, preserving source compatibility and existing direct callers. WhimService supplies defaults for Watch sessions. Duplicate starts do not replace the active policy.
- `DeviceSync/ConnectivityEnvelope.swift`: add `.watchRecordingPreferences(WatchRecordingPreferencesTransfer)`, carrying a monotonic revision and validated values, plus an applied acknowledgement carrying that revision. Keep the current envelope schema for additive payloads; old peers may ignore the new payload without blocking old message types.
- `DeviceSync/ConnectivityMergeService.swift`: accept the preference store as an optional dependency for existing callers; add `queueWatchRecordingPreferences(_ transfer: WatchRecordingPreferencesTransfer) async throws`. Apply newer values only on Watch, persist values and revision together before acknowledging, and ignore older/duplicate revisions within the current ResetGeneration. Preserve unrelated Watch preferences. Keep these messages independent of webhook configuration/credentials and use existing durable transfer, replay, and reset-generation rules.
- `Preferences/SettingsProjection.swift`: expose a separate Watch recording-preference sync status (`pending`, `synchronized`, or `unavailable`). Keep webhook synchronization time semantics intact.
- `src/iphone/preferences/SettingsEditor.swift` and `PreferencesView.swift`: edit and save the two fields with the existing native form conventions.
- Update explicit source/test lists in `packages/WhimCore/Package.swift`. Existing SwiftUI files are already included by the app project; inspect `ios/whim.xcodeproj/project.pbxproj` only if new app-target files are introduced.

## Detector proposal

- Consume paired meter samples using recording elapsed time, not wall-clock Date or SwiftUI timers.
- Start with meaningful audio at or above `RecordingLimits.meaningfulPeakPowerDBFS` (-45 dBFS) for at least 200 ms before arming. This avoids arming on a single peak; it does not promise semantic speech recognition.
- After arming, count consecutive samples at or below -50 dBFS as silence. Any higher level resets the interval. Keep both thresholds and the 200-ms arming duration in one internal configuration location; physical testing may justify tuning them before release.
- Stop when the observed continuous quiet interval reaches the selected duration and the session has lasted at least 2 seconds. At the default, 2.9 seconds of observed silence continues; 3.0 seconds requests one normal Stop.
- A gap greater than 500 ms between meter samples invalidates the quiet interval. Non-finite samples, backwards elapsed time, and route changes also invalidate timing; missing measurements must never be treated as silence. Backwards time resets the detector completely.
- Reset policy state for every new Recording Session and clear it on stop, discard, interruption, activation failure, and finalization failure.
- Bind an automatic-stop request to the session that produced it. Recheck that session identity before finalizing so an old scheduled request cannot stop a new session. Join the existing finalization/discard ownership rather than adding another save/send path.

## Review Focus

1. Legacy preferences must enable this feature without erasing retention, transcription, or locale choices — Slice 1.
2. Gaps in meter delivery and route changes must not fabricate silence or cut off quiet speech — Slice 2 and physical acceptance.
3. Auto-stop racing with manual Stop, Discard, interruption, or a new session must never duplicate or misattribute a Note — Slice 2.
4. Disconnected/restarted devices, out-of-order revisions, mixed app versions, and reset replay must converge without resurrecting an old preference — Slice 3.
5. Saving on the phone must affect subsequent offline Watch capture without requiring webhook configuration or stopping an existing session — Slices 3–5.

## Implementation slices

### Slice 1: Persist and migrate Watch preferences

**Files:** New WatchRecordingPreferences source/companions; `WhimClient.swift`; `WhimService.swift`; `AppComposition/WhimService.integration.test.swift`; `packages/WhimCore/Package.swift`.

- [ ] Add failing unit cases `testWatchRecordingDefaultsAreEnabledWithThreeSecondSilence`, `testLegacyPreferenceDecodingPreservesExistingValues`, and parameterized validation for accepted 2/3/10 seconds and rejected 1/11 seconds.
- [ ] Run `swift test --package-path packages/WhimCore --filter WhimCoreUnitTests`; confirm failures arise from the missing preferences behavior.
- [ ] Implement the value type, backward-compatible Codable fields, and validation at `WhimClient.updatePreferences` and peer decode/apply boundaries. Reject invalid values without partially saving unrelated preferences.
- [ ] Add failing integration cases `testWatchPreferencesSurviveStoreRecreation`, `testChangingUnrelatedPreferencesPreservesWatchPreferences`, and `testResetRestoresWatchRecordingDefaults`; implement only the persistence/reset behavior they require.
- [ ] Run `swift test --package-path packages/WhimCore --filter WhimCoreIntegrationTests` and the affected unit suite; require PASS. Commit this slice.

### Slice 2: Automatically finalize Watch capture after observed silence

**Files:** New SilenceAutoStopPolicy source; `AudioRecorder.swift`; `AVAudioRecorderAdapter.swift` and companion test; `RecordingService.swift` and companion tests; `RecordingLimits.swift`; `WhimService.swift` and integration companion; package source list.

**Consumes:** Slice 1 preferences. **Produces:** paired meter event and `RecordingService.start(source:autoStop:)` described above; automatic completion through existing `.finalized` events.

- [ ] Add a failing adapter-boundary test proving one meter event contains the elapsed time and level from the same hardware observation. Add a failing RecordingService test `testWatchSilenceFinalizesAtConfiguredDurationAfterMeaningfulAudio` asserting active capture at 2.9 quiet seconds and one completed Note at 3.0 quiet seconds.
- [ ] Run the affected WhimCore unit tests and observe the expected behavior failure. Add the minimum meter-event and policy implementation, with session-bound normal finalization.
- [ ] Add cases one at a time for duration endpoints 2/10, initial silence, a single loud peak, resumed audio, disabled auto-stop, iPhone exclusion, sample gaps, invalid/backwards samples, route changes, and a new Recording Session. Each test must fail before its behavior is implemented.
- [ ] Add concurrency regressions through RecordingService for auto-stop/manual Stop joining one finalization; Discard winning before auto-stop; interruption preserving its interrupted outcome; and an obsolete stop task not touching a subsequent session. Keep the five-minute stop/warning tests passing.
- [ ] Add a facade integration case using real RecordingService, SQLite, audio files, and Workflow modules with a fake microphone/network boundary. Assert one Note ID and one local workflow start; cover successful Delivery, offline Queued, missing configuration, and recoverable finalization failure at their existing seams. Do not assert globally exactly one HTTP Attempt: Watch/iPhone concurrent Attempts remain allowed.
- [ ] Run affected unit and core integration suites; require PASS. Commit this slice.

### Slice 3: Synchronize preferences and apply them to subsequent Watch sessions

**Files:** `ConnectivityEnvelope.swift`; `ConnectivityMergeService.swift` and both companions; `ConnectivityJournal.swift` if transactional outbox reconciliation is needed; `WhimService.swift` and integration companion; `SettingsProjection.swift`; `src/watch/recording/WatchModel.integration.test.swift`.

**Consumes:** persisted values/revision and session policy. **Produces:** durable preference transfer, applied acknowledgement/status, and local Watch policy selection.

- [ ] Add a failing cross-device integration test `testPhoneWatchPreferencesApplyWithoutWebhookConfiguration`. Save disabled/10 seconds through the real phone facade, route actual peer envelopes through a fake transport, restart the Watch service, and prove a new Recording Session uses those values through its observable behavior.
- [ ] Run `swift test --package-path packages/WhimCore --filter WhimCoreIntegrationTests`; confirm expected failure. Implement the additive payload and applied acknowledgement using the existing durable outbox.
- [ ] Save phone values and their incremented revision together in the existing preference record. Reconcile this record into the outbox after save and on launch/activation, so a crash between preference save and enqueue cannot lose synchronization. Do not wait for immediate reachability.
- [ ] On Watch, persist accepted values and revision together. Reject revisions lower than the stored one; equal revisions are harmless. Track applied acknowledgement separately from transport durability. Acknowledging receipt alone must not mark the UI synchronized.
- [ ] Add failing cases for two changes delivered backwards, duplicates, transport failure/replay, phone restart after save-before-enqueue, Watch restart, stale messages after reset, invalid payloads, and unsupported additive payloads alongside valid legacy messages. Reset preferences before replaying new-generation settings; ensure facade reset handling does not wipe a just-applied revision afterward.
- [ ] Add an integration case proving a mid-session update affects only the next capture and another proving capture does not await peer synchronization. Use the existing Watch-model integration target for launch/focus behavior.
- [ ] Run affected unit/core integration tests and `npm run test:integration` with its configured simulator pair; require PASS. Commit this slice.

### Slice 4: Expose and save controls under Settings → Apple Watch

**Files:** `src/iphone/preferences/SettingsEditor.swift`, `SettingsEditor.integration.test.swift`, `PreferencesView.swift`, and new `e2e/iphone/watch-silence-settings.e2e.test.yaml`.

**Consumes:** Slice 1 preference values and Slice 3 sync projection. **Produces:** toggle, adjustable slider, Save behavior, and pending/applied feedback.

- [ ] Add a failing SettingsEditor integration case `testWatchRecordingDraftSavesWithoutChangingOtherPreferences`. Assert default draft values, dirty/save state, persistence of disabled/10 seconds, and preservation of retention/transcription/locale. Add a failure case proving a rejected save retains the draft and exposes an error.
- [ ] Run `swift test --filter WhimIPhoneIntegrationTests.SettingsEditorIntegrationTests`; confirm expected failure. Extend the editor while preserving revision metadata for WhimService to manage.
- [ ] Add the installed iPhone journey before editing SwiftUI: navigate Settings → Apple Watch, find controls with enabled/3-second defaults, adjust to 2 and 10, Save, leave/reopen, toggle off/on while preserving duration, and verify unsaved navigation does not persist edits. Use stable identifiers `watch-auto-stop-enabled`, `watch-silence-duration`, and `watch-recording-sync-status`.
- [ ] Run the new journey with the runner's existing fixture environment; confirm expected failure. Implement the native Toggle/Slider and make the Watch section editable with its existing Save toolbar. Preserve access to the complication guide and existing sync/reset information.
- [ ] Verify slider adjustment using supported Maestro accessibility actions; if the runner cannot adjust a native Slider reliably, add a focused installed iOS XCTest accessibility test rather than a production-only test control. Manually check VoiceOver units and large text in physical acceptance.
- [ ] Run affected presentation integration tests and `npm run test:e2e:iphone`; require PASS. Commit this slice.

### Slice 5: Prove hands-free capture in installed builds and document acceptance

**Files:** `Recording/DebugFixtureRecorder.swift` and its integration companion; `e2e/watch/WatchRecording.e2e.test.swift`; `e2e/watch/WhimWatch.e2e.test.swift`; cross-device E2E companion; `e2e/physical/watch-capture.e2e.test.md`; canonical v1 design recording/Watch/settings/test sections.

- [ ] First add a failing fixture integration case for a DEBUG-only deterministic meter sequence: meaningful audio followed by silence, with a real playable audio file. Extend the existing fixture recorder to emit paired meter events. Keep its default sequence continuously meaningful so existing manual-stop journeys remain stable.
- [ ] Add a failing installed Watch test that launches into capture, feeds the sequence, never taps Stop, observes idle and one saved Note, and confirms Delivery through the existing loopback receiver. Add a disabled-mode journey requiring manual Stop. Use injected system boundaries; do not bypass RecordingService or invoke its stop method from the fixture.
- [ ] Add a cross-device installed journey: phone changes duration/enablement, Watch applies it, disconnect simulated transport, and the next capture obeys the cached choice. Keep detailed revision ordering assertions in integration tests.
- [ ] Run `npm run test:e2e:watch` and the affected cross-device/iPhone journeys; require PASS.
- [ ] Update the v1 behavior and physical acceptance procedure: app/complication/shortcut entry, initial delay before speaking, brief and long pauses, soft speech, quiet room, road noise, wind, wrist-down/background, manual Stop/Discard race, Bluetooth/route changes, disconnected Watch, and the unchanged five-minute safeguard. Require no premature cutoff and eventual stop after detectable silence; document noisy environments where the meter cannot identify silence. Confirm no extra Speech permission is requested.
- [ ] Run `npm run test:all` and `git diff --check`; require exit 0. Build the affected iPhone and Watch targets through the existing runners. Record physical acceptance separately; deterministic tests do not prove real microphone/background behavior. Commit the verified implementation and documentation.

## Planning verification

The issue and comments, canonical terminology/design, recording adapter/service, preference persistence/editor/view, peer protocol/journal, package source lists, fixture recorder, and existing automated runners were inspected. This change adds only this proposed plan. No application code was changed and no implementation tests were run.
