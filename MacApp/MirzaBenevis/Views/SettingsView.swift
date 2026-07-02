import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var modelManager: ModelManager
    @Environment(\.dismiss) private var dismiss

    @State private var geminiAPIKey = KeychainHelper.loadGeminiAPIKey() ?? ""
    @State private var showKey = false
    @State private var saved = false
    @State private var selectedModel = AppSettings.whisperModelSize
    @State private var useGPU = AppSettings.useGPU

    var body: some View {
        Form {
            Section("مدل whisper.cpp (on-device)") {
                Picker("مدل", selection: $selectedModel) {
                    ForEach(WhisperModelSize.allCases) { model in
                        HStack {
                            Text(model.label)
                            if modelManager.isModelDownloaded(model) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                        .tag(model)
                    }
                }
                .onChange(of: selectedModel) { _, v in AppSettings.whisperModelSize = v }

                if modelManager.isDownloading {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: modelManager.downloadProgress) {
                            HStack {
                                Text(modelManager.statusMessage)
                                Spacer()
                                if !modelManager.downloadSpeed.isEmpty {
                                    Text(modelManager.downloadSpeed)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        if modelManager.downloadProgress > 0 {
                            Text("\(Int(modelManager.downloadProgress * 100))%")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button("لغو دانلود", role: .destructive) {
                        modelManager.cancelDownload()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                } else {
                    if let error = modelManager.downloadError {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("خطا در دانلود", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                                .font(.caption)
                            Text(error)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                    }
                    Button("دانلود / به‌روزرسانی مدل") {
                        Task {
                            try? await modelManager.downloadModel(selectedModel)
                        }
                    }
                }

                Toggle("Metal / GPU (Apple Silicon)", isOn: $useGPU)
                    .onChange(of: useGPU) { _, v in AppSettings.useGPU = v }

                Text("مدل روی Neural Engine و Metal اجرا می‌شود — بدون سرور Python، بدون فشار به باتری.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("کلید API جمینای (خلاصه‌سازی)") {
                HStack {
                    if showKey {
                        TextField("AIza...", text: $geminiAPIKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("AIza...", text: $geminiAPIKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button { showKey.toggle() } label: {
                        Image(systemName: showKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                }

                Button("ذخیره") {
                    if KeychainHelper.saveGeminiAPIKey(geminiAPIKey) { saved = true }
                }
                .disabled(geminiAPIKey.isEmpty)

                if saved {
                    Label("ذخیره شد", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }

            Section("منبع صدا") {
                Picker("پیش‌فرض", selection: Binding(
                    get: { AppSettings.audioSource },
                    set: { AppSettings.audioSource = $0 }
                )) {
                    ForEach(AudioSourceMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.icon).tag(mode)
                    }
                }

                Text("ScreenCaptureKit صدای Zoom/Meet را بدون BlackHole ضبط می‌کند.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Core ML (اختیاری)") {
                Text("برای سرعت بیشتر encoder، مدل Core ML را از README پروژه whisper.cpp بسازید و در پوشه models قرار دهید.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .navigationTitle("تنظیمات")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("بستن") { dismiss() }
            }
        }
    }
}
