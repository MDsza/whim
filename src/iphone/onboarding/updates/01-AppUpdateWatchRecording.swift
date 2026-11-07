import SwiftUI
import WhimIPhone

struct AppUpdateWatchRecording: View {
    let editor: SettingsEditor

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            WatchRecordingControls(autoStopEnabled: Binding(
                get: { editor.watchAutoStopEnabled }, set: { editor.watchAutoStopEnabled = $0 }),
                silenceDurationSeconds: Binding(
                    get: { editor.watchSilenceDurationSeconds }, set: { editor.watchSilenceDurationSeconds = $0 }))
            Text("You can change this any time in Settings → Apple Watch.")
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("watch-recording-update")
    }
}
