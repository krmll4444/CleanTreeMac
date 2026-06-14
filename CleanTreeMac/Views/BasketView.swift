import SwiftUI
import UniformTypeIdentifiers

struct BasketView: View {
    let items: [BasketItem]
    let onRemove: (BasketItem) -> Void
    let onClear: () -> Void
    let onDelete: () -> Void
    let onDropPath: (String) -> Void

    @State private var isTargeted = false

    private var totalSize: Int64 {
        items.reduce(0) { $0 + $1.size }
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .strokeBorder(
                            isTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                            lineWidth: 2,
                            antialiased: true
                        )
                        .frame(width: 44, height: 44)

                    Image(systemName: items.isEmpty ? "target" : "trash")
                        .font(.title3)
                        .foregroundStyle(items.isEmpty ? .secondary : .primary)
                }

                if items.isEmpty {
                    Text("Перетягуйте сюди файли та папки")
                        .foregroundStyle(.secondary)
                    Spacer()
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(items) { item in
                                BasketChip(item: item) {
                                    onRemove(item)
                                }
                            }
                        }
                    }

                    VStack(alignment: .trailing, spacing: 4) {
                        Text(ByteFormat.string(for: totalSize))
                            .font(.headline.monospacedDigit())
                        Text("\(items.count) об'єкт(ів)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button("Очистити", role: .destructive, action: onClear)
                        .disabled(items.isEmpty)

                    Button("Видалити") {
                        onDelete()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(items.isEmpty)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(isTargeted ? Color.accentColor.opacity(0.12) : AppTheme.basketBackground)
            .onDrop(of: [.plainText, .utf8PlainText], isTargeted: $isTargeted) { providers in
                handleDrop(providers)
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.canLoadObject(ofClass: NSString.self) {
                provider.loadObject(ofClass: NSString.self) { object, _ in
                    guard let path = object as? String else { return }
                    Task { @MainActor in
                        onDropPath(path)
                    }
                }
                return true
            }
        }
        return false
    }
}

private struct BasketChip: View {
    let item: BasketItem
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(item.name)
                .lineLimit(1)
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(AppTheme.chipBackground)
        .clipShape(Capsule())
    }
}
