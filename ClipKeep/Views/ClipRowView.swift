import SwiftUI
import UIKit
import ClipKeepCore

struct ClipRowView: View {
    let item: ClipItem

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            preview

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if item.isPinned {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                    Text(item.title)
                        .lineLimit(item.kind == .text ? 3 : 2)
                        .truncationMode(.tail)
                        .font(.body)
                }

                HStack(spacing: 8) {
                    Label(item.kind.title, systemImage: item.kind.icon)
                    Text(Self.relativeFormatter.localizedString(for: item.updatedAt, relativeTo: .now))
                    Spacer()
                    Text(detailText)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var preview: some View {
        switch item.kind {
        case .text:
            Image(systemName: "text.alignleft")
                .font(.system(size: 18))
                .foregroundStyle(.blue)
                .frame(width: 38, height: 38)
                .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        case .image:
            if let image = item.thumbnailImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 42, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 18))
                    .foregroundStyle(.green)
                    .frame(width: 38, height: 38)
                    .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
        case .file:
            Image(systemName: "doc")
                .font(.system(size: 18))
                .foregroundStyle(.orange)
                .frame(width: 38, height: 38)
                .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var detailText: String {
        switch item.kind {
        case .text:
            return "\(item.content.count) 字符"
        case .image, .file:
            return item.byteCount.byteCountString
        }
    }
}

private extension ClipItem {
    var thumbnailImage: UIImage? {
        guard let url = ClipStore.shared.thumbnailURL(for: self) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}

private extension ClipKind {
    var title: String {
        switch self {
        case .text: return "文本"
        case .image: return "图片"
        case .file: return "文件"
        }
    }

    var icon: String {
        switch self {
        case .text: return "text.alignleft"
        case .image: return "photo"
        case .file: return "doc"
        }
    }
}

private extension Optional where Wrapped == Int {
    var byteCountString: String {
        guard let self else { return "未知大小" }
        return ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .file)
    }
}
