import SwiftUI
import ClipKeepCore

struct ClipRowView: View {
    let item: ClipItem

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                if item.isPinned {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                        .padding(.top, 2)
                }
                Text(item.content)
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .font(.body)
            }
            HStack {
                Text(Self.relativeFormatter.localizedString(for: item.updatedAt, relativeTo: .now))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(item.content.count) 字符")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
