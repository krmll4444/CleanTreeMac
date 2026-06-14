import SwiftUI

struct HomeScreenView: View {
    let volumeName: String
    let totalCapacity: Int64
    let availableCapacity: Int64
    let isScanning: Bool
    let onScan: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            HStack(alignment: .center, spacing: 24) {
                HStack(spacing: 16) {
                    Image(systemName: "internaldrive.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.secondary)
                        .symbolRenderingMode(.hierarchical)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(volumeName)
                            .font(.title.bold())

                        HStack(spacing: 16) {
                            Label(ByteFormat.string(for: totalCapacity), systemImage: "chart.pie")
                            Label("\(ByteFormat.string(for: availableCapacity)) вільно", systemImage: "tray")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button(action: onScan) {
                    Label("Сканувати", systemImage: "arrow.clockwise")
                        .font(.headline)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isScanning)
            }
            .padding(28)
            .background(AppTheme.panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
            .padding(.horizontal, 40)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.windowBackground)
    }
}

#Preview {
    HomeScreenView(
        volumeName: "Macintosh HD",
        totalCapacity: 500_000_000_000,
        availableCapacity: 120_000_000_000,
        isScanning: false,
        onScan: {}
    )
    .frame(width: 700, height: 400)
}
