import SwiftUI

struct ScanSettingsView: View {
    let selectedPaths: [String]
    let isScanning: Bool
    let onTogglePath: (String) -> Void

    private var selectablePaths: [String] {
        ScanSettings.selectablePaths
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Що сканувати")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(selectablePaths, id: \.self) { path in
                Toggle(isOn: toggleBinding(for: path)) {
                    Label(SystemPaths.displayName(for: URL(fileURLWithPath: path, isDirectory: true)), systemImage: icon(for: path))
                        .font(.subheadline)
                }
                .toggleStyle(.checkbox)
                .disabled(isScanning)
            }
        }
    }

    private func toggleBinding(for path: String) -> Binding<Bool> {
        Binding(
            get: { selectedPaths.contains(path) },
            set: { _ in onTogglePath(path) }
        )
    }

    private func icon(for path: String) -> String {
        switch path {
        case "/Users": "person.2"
        case "/Applications": "app.grid"
        case "/Library": "books.vertical"
        default: "folder"
        }
    }
}

#Preview {
    ScanSettingsView(
        selectedPaths: ["/Users", "/Applications"],
        isScanning: false,
        onTogglePath: { _ in }
    )
    .padding()
    .frame(width: 280)
}
