import SwiftUI

struct SessionsListView: View {
    @EnvironmentObject var transcriptStore: TranscriptStore
    @State private var selectedSession: TranscriptionSession?
    @State private var isSummarizing = false
    @State private var summaryError: String?
    @State private var exportMessage: String?
    @State private var geminiAPIKey = KeychainHelper.loadGeminiAPIKey() ?? ""

    var body: some View {
        HSplitView {
            sessionsList
                .frame(minWidth: 220, idealWidth: 260)

            sessionDetail
        }
        .navigationTitle("جلسات")
    }

    private var sessionsList: some View {
        List(transcriptStore.sessions, selection: $selectedSession) { session in
            VStack(alignment: .leading, spacing: 4) {
                Text(session.title)
                    .font(.headline)
                Text("\(session.wordCount) کلمه")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(session.createdAt, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .tag(session)
        }
        .onAppear {
            if selectedSession == nil {
                selectedSession = transcriptStore.sessions.first
            }
        }
    }

    @ViewBuilder
    private var sessionDetail: some View {
        if let session = selectedSession {
            SessionDetailView(
                session: session,
                geminiAPIKey: geminiAPIKey,
                isSummarizing: $isSummarizing,
                summaryError: $summaryError,
                exportMessage: $exportMessage
            )
        } else {
            ContentUnavailableView(
                "جلسه‌ای انتخاب نشده",
                systemImage: "doc.text",
                description: Text("یک جلسه از لیست انتخاب کنید")
            )
        }
    }
}

struct SessionDetailView: View {
    let session: TranscriptionSession
    let geminiAPIKey: String
    @Binding var isSummarizing: Bool
    @Binding var summaryError: String?
    @Binding var exportMessage: String?
    @EnvironmentObject var transcriptStore: TranscriptStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                exportSection
                audioSection
                transcriptSection
                summarySection
            }
            .padding()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(session.title)
                    .font(.title2.bold())
                Text("\(session.wordCount) کلمه | \(session.createdAt.formatted())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .destructive) {
                transcriptStore.deleteSession(session)
            } label: {
                Label("حذف", systemImage: "trash")
            }
        }
    }

    private var exportSection: some View {
        GroupBox("خروجی") {
            HStack(spacing: 12) {
                ForEach(ExportFormat.allCases) { format in
                    Button {
                        exportSession(format: format)
                    } label: {
                        Label(format.label, systemImage: format == .pdf ? "doc.richtext" : "doc.text")
                    }
                    .disabled(session.fullText.isEmpty)
                }

                if let exportMessage {
                    Text(exportMessage)
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
    }

    @ViewBuilder
    private var audioSection: some View {
        if let audioURL = session.audioFileURL {
            GroupBox("فایل صوتی") {
                HStack(spacing: 12) {
                    Button {
                        NSWorkspace.shared.open(audioURL)
                    } label: {
                        Label("پخش", systemImage: "play.circle.fill")
                    }

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([audioURL])
                    } label: {
                        Label("نمایش در Finder", systemImage: "folder")
                    }

                    Spacer()

                    if let size = try? FileManager.default.attributesOfItem(atPath: audioURL.path)[.size] as? Int64 {
                        Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var transcriptSection: some View {
        GroupBox("رونوشت کامل") {
            Text(session.fullText.isEmpty ? "—" : session.fullText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var summarySection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("خلاصه جمینای")
                        .font(.headline)
                    Spacer()
                    Button {
                        Task { await generateSummary() }
                    } label: {
                        if isSummarizing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("خلاصه‌سازی", systemImage: "sparkles")
                        }
                    }
                    .disabled(isSummarizing || session.fullText.isEmpty || geminiAPIKey.isEmpty)
                }

                if geminiAPIKey.isEmpty {
                    Text("ابتدا کلید API جمینای را در تنظیمات وارد کنید.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if let error = summaryError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if let summary = session.summary ?? transcriptStore.sessions
                    .first(where: { $0.id == session.id })?.summary {
                    Text(summary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("هنوز خلاصه‌ای ساخته نشده")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func exportSession(format: ExportFormat) {
        exportMessage = nil
        do {
            if let url = try ExportService.export(session: session, format: format) {
                exportMessage = "ذخیره شد: \(url.lastPathComponent)"
            }
        } catch {
            exportMessage = nil
            summaryError = error.localizedDescription
        }
    }

    private func generateSummary() async {
        isSummarizing = true
        summaryError = nil
        defer { isSummarizing = false }

        do {
            let summary = try await GeminiService.summarize(
                text: session.fullText,
                apiKey: geminiAPIKey
            )
            transcriptStore.setSummary(summary, for: session.id)
        } catch {
            summaryError = error.localizedDescription
        }
    }
}
