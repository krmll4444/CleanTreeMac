import SwiftUI

struct BreadcrumbView: View {
    let breadcrumb: [FileNode]
    let onSelect: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Text("Диски та папки")
                    .foregroundStyle(.secondary)

                if !breadcrumb.isEmpty {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                ForEach(Array(breadcrumb.enumerated()), id: \.element.id) { index, node in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Button(node.name) {
                        onSelect(index)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(index == breadcrumb.count - 1 ? .primary : .secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }
}
