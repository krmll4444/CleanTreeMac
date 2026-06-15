import AppKit
import SwiftUI

struct ScanProgressPanel: View {
    let progress: Double
    let logLines: [ScanLogEntry]
    let status: String
    let scanStartDate: Date?
    let onCancel: () -> Void

    @State private var didCopyLog = false

    var body: some View {
        VStack(spacing: 0) {
            ProgressView(value: progress, total: 1.0)
                .progressViewStyle(.linear)
                .tint(.accentColor)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(AppTheme.barBackground)

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("CleanTreeMac — scan")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.terminalMuted)
                    Spacer()
                    if let scanStartDate {
                        ScanElapsedLabel(startDate: scanStartDate)
                    }
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(AppTheme.terminalMuted)
                        .lineLimit(1)
                    Button("Скасувати", action: onCancel)
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Button(action: copyLogToClipboard) {
                        Label(
                            didCopyLog ? "Скопійовано" : "Копіювати",
                            systemImage: didCopyLog ? "checkmark" : "doc.on.doc"
                        )
                        .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(didCopyLog ? .green : AppTheme.terminalMuted)
                    .disabled(logLines.isEmpty)
                    .help("Копіювати весь лог")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppTheme.terminalHeader)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(logLines) { entry in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(entry.timestamp)
                                        .foregroundStyle(AppTheme.terminalMuted)
                                    Text(entry.message)
                                        .foregroundStyle(AppTheme.terminalText)
                                }
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .id(entry.id)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contextMenu {
                        Button("Копіювати все") {
                            copyLogToClipboard()
                        }
                        .disabled(logLines.isEmpty)
                    }
                    .onChange(of: logLines.count) { _, count in
                        guard count > 0, let last = logLines.last else { return }
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            .frame(height: 120)
            .background(AppTheme.terminalBackground)
        }
    }

    private func copyLogToClipboard() {
        guard !logLines.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(logLines.clipboardText, forType: .string)
        didCopyLog = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            didCopyLog = false
        }
    }
}

private struct ScanElapsedLabel: View {
    let startDate: Date

    var body: some View {
        TimelineView(.periodic(from: startDate, by: 1)) { context in
            Label(
                ScanDurationFormat.string(for: context.date.timeIntervalSince(startDate)),
                systemImage: "timer"
            )
            .font(.caption.monospacedDigit())
            .foregroundStyle(AppTheme.terminalMuted)
        }
    }
}

#Preview {
    ScanProgressPanel(
        progress: 0.45,
        logLines: [
            .make("$ du -x -k -d 2 /"),
            .make("→ Аналіз: Macintosh HD…"),
            .make("→ знайдено 128 папок"),
            .make("→ Аналіз: /Users")
        ],
        status: "Сканування…",
        scanStartDate: Date().addingTimeInterval(-83),
        onCancel: {}
    )
    .frame(width: 700)
}
