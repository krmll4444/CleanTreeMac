import SwiftUI

struct SunburstChartView: View {
    let items: [DisplayItem]
    let totalSize: Int64
    let centerTitle: String
    let hoveredNodeID: UUID?
    let onHover: (UUID?) -> Void
    let onSelect: (DisplayItem) -> Void

    private let centerRadius: CGFloat = 72

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let segments = makeSegments(totalDiameter: size)

            ZStack {
                ForEach(segments) { segment in
                    SunburstSegmentShape(
                        startAngle: segment.startAngle,
                        endAngle: segment.endAngle,
                        innerRadius: segment.innerRadius,
                        outerRadius: segment.outerRadius
                    )
                    .fill(segment.color.opacity(segment.isHovered ? 1 : 0.88))
                    .overlay {
                        SunburstSegmentShape(
                            startAngle: segment.startAngle,
                            endAngle: segment.endAngle,
                            innerRadius: segment.innerRadius,
                            outerRadius: segment.outerRadius
                        )
                        .stroke(AppTheme.segmentStroke, lineWidth: 1)
                    }
                    .onTapGesture {
                        onSelect(segment.item)
                    }
                    .onHover { hovering in
                        onHover(hovering ? segment.node.id : nil)
                    }
                }

                Circle()
                    .fill(AppTheme.chartCenterFill)
                    .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
                    .frame(width: centerRadius * 2, height: centerRadius * 2)
                    .overlay {
                        VStack(spacing: 4) {
                            Text(centerTitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                            Text(ByteFormat.string(for: totalSize))
                                .font(.title2.bold())
                                .foregroundStyle(.primary)
                        }
                        .padding(8)
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func makeSegments(totalDiameter: CGFloat) -> [SunburstSegment] {
        guard !items.isEmpty else { return [] }

        let effectiveTotal = max(totalSize, items.reduce(Int64(0)) { $0 + $1.node.displaySize })
        guard effectiveTotal > 0 else { return [] }

        let outerBase = totalDiameter / 2 - 8
        var start = Angle.degrees(-90)
        var result: [SunburstSegment] = []

        for item in items {
            let fraction = Double(item.node.displaySize) / Double(effectiveTotal)
            let sweep = Angle.degrees(360 * fraction)
            let end = start + sweep

            let color: Color
            if item.isGroupedSmall {
                color = AppTheme.smallSegmentFill
            } else if item.node.kind == .hiddenSpace {
                color = .purple.opacity(0.65)
            } else {
                color = Color(hue: ChartPalette.hue(for: max(item.colorIndex, 0)), saturation: 0.62, brightness: 0.72)
            }

            result.append(
                SunburstSegment(
                    item: item,
                    startAngle: start,
                    endAngle: end,
                    innerRadius: centerRadius,
                    outerRadius: outerBase,
                    color: color,
                    isHovered: hoveredNodeID == item.node.id
                )
            )
            start = end
        }

        return result
    }
}

private struct SunburstSegment: Identifiable {
    let id: UUID
    let item: DisplayItem
    let node: FileNode
    let startAngle: Angle
    let endAngle: Angle
    let innerRadius: CGFloat
    let outerRadius: CGFloat
    let color: Color
    let isHovered: Bool

    init(
        item: DisplayItem,
        startAngle: Angle,
        endAngle: Angle,
        innerRadius: CGFloat,
        outerRadius: CGFloat,
        color: Color,
        isHovered: Bool
    ) {
        self.id = item.id
        self.item = item
        self.node = item.node
        self.startAngle = startAngle
        self.endAngle = endAngle
        self.innerRadius = innerRadius
        self.outerRadius = outerRadius
        self.color = color
        self.isHovered = isHovered
    }
}

private struct SunburstSegmentShape: Shape {
    let startAngle: Angle
    let endAngle: Angle
    let innerRadius: CGFloat
    let outerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()

        path.addArc(
            center: center,
            radius: outerRadius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        path.addArc(
            center: center,
            radius: innerRadius,
            startAngle: endAngle,
            endAngle: startAngle,
            clockwise: true
        )
        path.closeSubpath()
        return path
    }
}

#Preview {
    SunburstChartView(
        items: [],
        totalSize: 1_000_000_000,
        centerTitle: "Chrome",
        hoveredNodeID: nil,
        onHover: { _ in },
        onSelect: { _ in }
    )
    .frame(width: 400, height: 400)
    .background(AppTheme.windowBackground)
}
