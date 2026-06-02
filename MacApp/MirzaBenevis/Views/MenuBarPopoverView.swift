import SwiftUI

struct MenuBarPopoverView: View {
    @ObservedObject var coordinator: RecordingCoordinator
    @EnvironmentObject var transcriptStore: TranscriptStore
    @EnvironmentObject var modelManager: ModelManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            controls
            Divider()
            liveTranscript
            footer
        }
        .padding(14)
        .frame(width: 360)
        .task {
            await coordinator.prepareModel()
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: coordinator.isActive ? "mic.fill" : "waveform")
                .foregroundStyle(coordinator.isActive ? .red : .primary)
                .symbolEffect(.pulse, isActive: coordinator.isActive)

            VStack(alignment: .leading, spacing: 2) {
                Text("Mirza Benevis")
                    .font(.headline)
                Text(coordinator.statusMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if coordinator.whisperEngine.isProcessing {
                ProgressView().controlSize(.small)
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            HStack {
                Picker("منبع", selection: $coordinator.audioSource) {
                    ForEach(AudioSourceMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .disabled(coordinator.isActive)
                .onChange(of: coordinator.audioSource) { _, v in AppSettings.audioSource = v }

                Picker("زبان", selection: $coordinator.selectedLanguage) {
                    Text("فا").tag("fa" as String?)
                    Text("en").tag("en" as String?)
                    Text("auto").tag(nil as String?)
                }
                .pickerStyle(.menu)
                .frame(width: 70)
                .disabled(coordinator.isActive)
            }

            HStack(spacing: 8) {
                Button {
                    Task {
                        if coordinator.isActive {
                            await coordinator.stopRecording()
                        } else {
                            await coordinator.startRecording()
                        }
                    }
                } label: {
                    Label(
                        coordinator.isActive ? "توقف" : "شروع ضبط",
                        systemImage: coordinator.isActive ? "stop.circle.fill" : "record.circle"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(coordinator.isActive ? .red : .accentColor)
                .disabled(!coordinator.whisperEngine.isModelLoaded && !coordinator.isActive)

                Button {
                    coordinator.copyCurrentTranscript()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .help("کپی در کلیپ‌بورد")
                .disabled(transcriptStore.currentSession?.fullText.isEmpty ?? true)
            }

            if !coordinator.whisperEngine.isModelLoaded, let err = coordinator.whisperEngine.loadError {
                Text(err)
                    .font(.caption2)
                    .foregroundStyle(.red)
            } else if modelManager.isDownloading {
                ProgressView(value: modelManager.downloadProgress) {
                    Text("دانلود مدل...")
                        .font(.caption2)
                }
            }
        }
    }

    private var liveTranscript: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("رونوشت زنده")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            ScrollView {
                if let words = transcriptStore.currentSession?.words, !words.isEmpty {
                    Text(words.map(\.text).joined(separator: " "))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("متن اینجا نمایش داده می‌شود...")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                }
            }
            .frame(height: 120)
        }
    }

    private var footer: some View {
        HStack {
            Button("جلسات") { openWindow(id: "sessions") }
            Button("تنظیمات") { openWindow(id: "settings") }
            Button("خروج") {
                NSApplication.shared.terminate(nil)
            }
            .foregroundStyle(.red)
            Spacer()
            Text("\(transcriptStore.currentSession?.wordCount ?? 0) کلمه")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct SessionsWindowView: View {
    @EnvironmentObject var transcriptStore: TranscriptStore

    var body: some View {
        SessionsListView()
            .frame(minWidth: 800, minHeight: 500)
    }
}

struct SettingsWindowView: View {
    var body: some View {
        SettingsView()
    }
}
