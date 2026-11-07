import SwiftUI

struct OnboardingMicrophone: View {
    let microphoneDenied: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            OnboardingMicrophoneHeading()
            if microphoneDenied {
                Label("Enable microphone access in Settings to record.", systemImage: "mic.slash")
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct OnboardingMicrophoneHeading: View {
    var body: some View {
        OnboardingHeading(title: "Always ready to record",
            detail: "Whim uses your microphone only when you record.")
    }
}
