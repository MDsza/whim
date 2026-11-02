# iPhone and Apple Watch startup

Updated 2026-11-02 for immediate iPhone Record availability. These are ordered milestones, not measured device timings. SwiftUI rendering and independent tasks can interleave.

Both apps mount their destination shell immediately. iPhone uses its persisted onboarding flag to choose the introductory page or idle capture shell; Watch shows its capture shell. After onboarding, the iPhone shell accepts Record on its first frame and queues the request through shared service construction. Capture does not wait for the initial startup projection, recovery inventory, history, audio validation, optional permissions, webhook credentials, or synchronization.

## Timeline

| Stage | iPhone | Apple Watch | Background work |
| --- | --- | --- | --- |
| 1: first app frame | Introductory onboarding or idle capture shell, using the local onboarding hint. | Capture shell. | Construct the service and platform adapters off the main actor; open/migrate the database and create audio directories. |
| 2: model mounted | Subscribe to events and request the lightweight startup projection. | Subscribe to events and request the lightweight startup projection. | Watch Connectivity activates independently. |
| 3: capture preparation | Record remains available while shared service construction and initial checks finish. | Keep capture visible with preparation feedback. | Finish any pending destructive reset. Recovery inventory and audio validation run in independent maintenance. |
| 4: startup projection | Publish onboarding completion, microphone status, and active Recording Session. Reconcile the already interactive home; onboarding can advance. | Publish microphone/session state. First activation with granted permission starts capture automatically. | Microphone and onboarding reads are independent. Full settings and history load separately afterward. |
| 5: recording | User taps Record; claim audio ownership, persist a Recording Session, start hardware, and display the active recorder. | Start hardware and display elapsed time, Stop, and Discard with the start haptic. | Replay prior peer state, recover/validate old audio, resume eligible Workflows, and submit synchronization. Optional settings do not hold the capture queue. |
| 6: continued use | Stop publishes the saved Note immediately. Onboarding completion refreshes routing without joining history. | Stop returns to idle; history refresh follows independently. | Local history and playback read saved data independently of maintenance. History/settings failures remain independently actionable. |

```mermaid
flowchart TD
    A[Mount destination shell / Record after onboarding] --> B[Construct service / open storage]
    A --> R[Tap Record / queue capture]
    R --> B
    C --> S[Authorize microphone / persist session / start activity and hardware]
    B --> C[Resolve pending reset / wire events]
    C --> D[Lightweight startup projection]
    D --> E{Device}
    E -- iPhone --> F{Onboarding complete?}
    F -- No --> G[Interactive onboarding]
    F -- Yes --> H[Idle capture / Record]
    E -- Watch --> I{Permission granted and first activation?}
    I -- Yes --> J[Start Recording Session]
    I -- No --> K[Permission controls or restored capture state]
    D --> L[History and full settings load independently]
    C --> M[Peer replay → inventory and old audio recovery → pending work]
```

The iPhone accepts a Record request before initial checks finish. Only the command in flight disables repeated taps; Whim never claims the microphone is recording before hardware startup succeeds. Unknown Watch permission shows preparation feedback rather than an incorrect Allow microphone prompt.

## What still must precede capture

Database/schema availability, usable audio paths, event observation, pending destructive reset, microphone authorization, durable Recording Session creation, and required Live Activity startup remain prerequisites for actual capture. Recovery inventory and decoding are deferred. The UI accepts a tap while service construction finishes.

Recovery processes only inventoried candidates; enumeration may overlap capture. File-descriptor ownership prevents it from finalizing audio belonging to a live Recording Session, including one created by a separately composed client. Candidates discarded since enumeration are ignored. Playable remnants become review-required Notes; they are never automatically delivered.

Prior peer mutations precede old-audio validation because both can affect the same Notes. Destructive reset and deletion pause new maintenance, cancel/join existing work, and then erase. New capture does not wait for ordinary maintenance; destructive operations deliberately retain coordination with capture. A maintenance error does not prevent Reset Whim from clearing the store.

## iPhone routing and onboarding

The canonical lightweight projection replaces the persisted routing hint after preparation. Pending reset can return iPhone to onboarding. Webhook availability does not gate entry to capture.

Onboarding remains: **Get started → configure/test webhook or skip → microphone permission or continue without it**. The introduction appears before full settings; the configuration editor loads independently. Completing onboarding updates routing immediately and schedules auxiliary refresh afterward. Speech and notification permission offers remain contextual after a saved Note.

Opening iPhone does not start recording automatically. A warm scene activation restores state. Existing deep links can navigate to settings or a Note after navigation preparation. During capture, history/settings navigation remains unavailable.

Sources: [app entry](../src/iphone/app-composition/WhimIPhoneApp.swift), [routing](../src/iphone/app-composition/IPhoneRootView.swift), [presentation model](../src/iphone/app-composition/IPhoneModel.swift), [onboarding](../src/iphone/onboarding/OnboardingView.swift).

## Watch lifecycle

Watch has no separate onboarding. Granted permission on first model activation starts one Recording Session. Undetermined permission exposes Allow microphone after preparation; granting the request starts capture. Denied/restricted access shows an actionable error with device-specific guidance.

Returning after wrist-down or after Stop restores state without starting another Recording Session. Returning from Settings refreshes permission; after the first activation, Record remains an explicit action. Existing sessions are restored without duplicate start haptics. Crash recovery produces a review-required Note rather than resuming an old microphone session.

The Watch runtime shares one composition task between foreground and Watch Connectivity background entry points. A background callback starts maintenance and participates in background-task completion accounting, without constructing a model or auto-starting capture.

Sources: [app/runtime](../src/watch/app-composition/WhimWatchApp.swift), [activation](../src/watch/recording/WatchModel.swift), [capture screen](../src/watch/recording/WatchRecorderView.swift).

## Errors

Both devices show a rounded Liquid Glass container in the upper part of the screen. Earlier supported systems use material; Reduce Transparency uses an opaque background. Messages are sanitized and wrap to their content size. The compact card itself is the recovery action: tap anywhere on its glass surface. There is no separate action button or reserved scrolling area. VoiceOver announces the action; auxiliary errors can be dismissed with a horizontal swipe or the accessibility action.

- Preparation/capture failures offer Try again.
- Microphone denial opens iPhone Settings or Watch instructions.
- Storage exhaustion offers instructions and Check again.
- History/settings failures offer targeted retries and can be dismissed.
- Background maintenance failures identify recovery/synchronization as the failed work; local history and playback stay available.
- Playback failures explain the audio/player problem and retry the same Note. The glass container is hosted in the open history sheet, above its content, and clears when leaving history.
- Unrelated failed actions offer Refresh rather than repeating a recording command.

Capture-blocking errors take precedence. A blocking condition discovered after iPhone capture starts stops and finalizes it, preserves usable audio, and announces why recording stopped. If finalization fails, the existing recoverable Recording Session remains on disk with its local error. Unrelated recovery, history, settings, or synchronization failures do not stop capture. System failures are not rendered as raw exception strings. Service construction and failed maintenance can be retried; configuration-test audio is resolved when the user invokes Test webhook rather than during ordinary production startup.

## Verification and remaining measurement

### Shortcut and Control Center startup

Record a Whim performs its non-UI work outside the main actor, using the shared
`WhimRuntime` and the same canonical Recording Session as the app. On iOS 26 and
later, both the app and recording control explicitly prefer background execution
while allowing dynamic foreground continuation for microphone/activity recovery.
This follows Apple's [supportedModes guidance](https://developer.apple.com/documentation/appintents/appintent/supportedmodes).
Earlier systems retain the existing `openAppWhenRun` and foreground-continuation
behavior. Live Activity creation still precedes microphone activation.

The regression suite occupies the main actor while invoking the real Record
intent through WhimService and verifies that the activity boundary is reached.
Built-metadata verification checks the background preference in both bundles so
the control and shortcut cannot silently advertise different execution modes.

Investigation on the iPhone 18 Pro / iOS 27 simulator also found a separate cold
dispatch delay: iOS took roughly 2.5–4.6 seconds between its shortcut assertion
and invoking `perform()`. Once invoked, a warm Whim requested its activity in
about 30–50 ms. Removing the UI-actor dependency, preferring background execution,
using background-only execution, and a throwaway lightweight scene did not remove
the cold system-dispatch interval. The latter two experiments were discarded.
These measurements do not establish that the reported end-to-end delay is fixed.
First visible recording content must be measured separately from the system's
initial expanded activity toast and its later compact Island presentation.
Temporary startup probes measured only a few milliseconds in Whim's onboarding
store/background-task registration and under 100 ms in service/model preparation.
A changing-signal fixture also completed its initial archive while publishing
repeated updates; with a warm renderer, constant and changing signals both reached
internal content readiness in about 1.2–1.3 seconds. These probes were removed;
the evidence does not justify adding an arbitrary initial meter-update delay.

A bounded 2026-11-02 comparison of the final code on the same iPhone 18 Pro / iOS 27 simulator measured app-launch assertion → `perform()` at 3.190 seconds in Debug and 2.036 seconds in Release. `perform()` → activity request was 174 ms and 43 ms respectively. These are one sample per configuration, with a previously initialized simulator; they measure dispatch and the API request, not first visible activity content. Optimization reduced the measured interval but did not eliminate cold dispatch. The optimized build was installed for the final simulator preview.

Regression tests hold old recovery, optional settings, or webhook-test HTTP unfinished and verify that capture/Stop still completes. Presentation tests verify that onboarding completion does not join the slow auxiliary refresh. Recovery tests verify live-writer exclusion even when inventory is taken during capture. Tests also hold inventory and the initial presentation projection unfinished while Record/Stop completes, and inject a late storage-full failure to verify stopping, audio preservation, and an actionable explanation. The immediate-record-on-launch installed journey holds automatic composition and verifies the first shell accepts Record without preparation text. Installed journeys cover permission guidance and preparation failure/retry.

These prove dependency removal, not a numeric cold-launch speedup. Real-device measurements should record first destination appearance and microphone onset separately, for cold/warm launches and empty/populated stores. Physical acceptance also checks wrist-down capture and initial speech preservation. See [iPhone acceptance](../e2e/physical/iphone-presentation.e2e.test.md) and [Watch acceptance](../e2e/physical/watch-capture.e2e.test.md).

Core sources: [WhimClient](../packages/WhimCore/Sources/WhimCore/AppComposition/WhimClient.swift), [service and composition](../packages/WhimCore/Sources/WhimCore/AppComposition/WhimService.swift), [recovery](../packages/WhimCore/Sources/WhimCore/Recovery/RecoveryScanner.swift), [audio ownership](../packages/WhimCore/Sources/WhimCore/Notes/AudioFileStore.swift).


## Follow-up regression: apparent missing history and failed playback

The first implementation kept `listNotes`, Note detail, waveform, and playback behind the full `launch()` maintenance gate. A failure in recovery or synchronization therefore prevented any history snapshot from reaching the interface, even with valid metadata and audio on disk. A fresh model displayed an empty list; newly captured Notes appeared via events, but their playback hit the same failed gate. This explains the reproduced symptom without requiring deletion. The prior startup tests covered capture independence but missed local browsing/playback during maintenance failure.

Local reads and playback now join only essential preparation. `WhimClient.maintain()` runs independently and reports a separate error; completion refreshes history. Deletion cancels and joins maintenance, then presentation resumes remaining recovery. Targeted tests reproduce a sent Note and a new Note remaining playable after failed recovery, history survival, delete-during-recovery resumption, and playback retry within the modal. The installed `playback-error` journey verifies that the message and action are visible without dismissing history.

The reported physical iPhone was updated in place. The production storage path was unchanged by this patch. The paired device was inspected read-only after connection. Apple’s device file service refused the top-level `Whim/whim.sqlite` path because only `Library`, `Documents`, and `tmp` are exposed. The actual stored Note count and original maintenance exception therefore remain unverified; an empty exposed-container listing is not evidence of deletion. No reset, deletion, reinstall, or repair was performed on that physical device.
