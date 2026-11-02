# Immediate iPhone recording

The user's updated policy is authoritative: opening Whim must offer Record immediately; a blocking condition discovered after capture begins stops capture and explains the reason. Preserve playable captured audio. Optional history, recovery, settings, and synchronization work must not delay capture or stop it for an unrelated failure.

Implement natively in the existing worktree, preserving the shortcut changes already present.

- [x] Add failing WhimCore integration coverage with recovery inventory suspended; startup and Record/Stop must finish independently. Keep live-writer recovery exclusion covered.
- [x] Move recovery inventory into maintenance. Retain event subscription, pending destructive reset coordination, microphone authorization, durable Recording Session creation, and required Live Activity startup as capture necessities.
- [x] Add failing presentation coverage for Record/Stop before startup projection completes and for a late storage-full condition stopping and preserving the current recording with an actionable error.
- [x] Make model capture commands publish their returned state immediately, without joining a startup refresh. Keep Record available before initial checks complete. Stop and explain genuine blocking failures; retain ordinary recovery-failure independence.
- [x] Offer the existing Record control in the first startup shell. Queue its action through the shared runtime and mount exactly one presentation model. Add installed cold-launch coverage with a DEBUG-only held startup task.
- [x] Update the v1 startup policy, run affected suites and `test:all`, review, and install the verified build on iPhone 18 Pro.

Public seams: WhimClient, platform adapters, native iPhone presentation, and the installed app, as specified in the v1 design. No artificial claim that the microphone is recording before hardware start succeeds. No new automatic capture merely from opening the iPhone app.

Regression evidence so far: held-inventory test failed before deferral, then the 42-test service suite passed. Held-startup/late-storage tests failed before the presentation change, then all 38 model tests passed. A later Shortcut inherited the storage-stop notice in a failing regression; session-scoped notices fixed it. Installed held-startup coverage failed on the original shell, then caught merged accessibility on the new button; the explicit accessibility container passed the complete first-Record/Stop/save journey. Both review findings were addressed; the 38-test model suite passed again. Full test:all is running (log: /tmp/whim-immediate-test-all.log).

The first full run caught the shared onboarding gate treating denied microphone access as disabled onboarding navigation. Onboarding now gates only its initial projection/command, independently of capture eligibility; existing denied/resume installed journeys reproduce it. The same run caught timing in the old keyboard-toolbar test. Waiting for its animation then using the semantic Done control passed the complete webhook/save/test/record/delivery journey. Full test:all restarted with both fixes (log: /tmp/whim-immediate-test-all-final.log).

Final verification: `npm run test:all` exited 0 on 2026-11-02 (log: /tmp/whim-immediate-test-all-final.log). All 22 iPhone journeys and all 18 Watch E2E cases passed, alongside unit/integration/native audio/system-surface checks. The final iPhone 18 Pro manual check held automatic startup for 120 seconds: the first shell exposed Record, its first tap entered capture, and Stop saved a Note. Capture and Stop/save also worked with the real audio adapter. Debug and Release simulator builds succeeded. A bounded optimized cold-Control-Center comparison still found a pre-perform dispatch interval (documented in startup-flow.md); the original end-to-end Shortcut delay is not claimed fixed. Working-tree changes remain available for review; no merge or push was requested.
