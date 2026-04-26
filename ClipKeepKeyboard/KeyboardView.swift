import SwiftUI
import UIKit
import ClipKeepCore

struct KeyboardView: View {
    @ObservedObject var store: KeyboardStore
    let onSelect: (ClipItem) -> Bool
    let onDeleteBackward: () -> Void
    let onDismiss: () -> Void

    @State private var searchText = ""
    @State private var selectedFilter: ClipFilter = .all
    @State private var notice: String?
    @State private var noticeTask: Task<Void, Never>?

    private var displayedItems: [ClipItem] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.items
            .filter { selectedFilter.matches($0) }
            .filter { q.isEmpty || $0.searchableText.localizedCaseInsensitiveContains(q) }
            .prefix(50)
            .map { $0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            filterBar
            Divider().opacity(0.45)
            content
            Divider().opacity(0.45)
            toolbar
        }
        .background(Color(UIColor.systemBackground))
        .onDisappear {
            noticeTask?.cancel()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label("ClipKeep", systemImage: "list.clipboard")
                .font(.system(size: 13, weight: .semibold))
                .labelStyle(.titleAndIcon)

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("搜索", text: $searchText)
                    .font(.system(size: 13))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .frame(width: 150, height: 30)
            .background(Color(UIColor.secondarySystemFill), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var filterBar: some View {
        Picker("类型", selection: $selectedFilter) {
            ForEach(ClipFilter.allCases) { filter in
                Text(filter.title).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .font(.system(size: 11))
        .padding(.horizontal, 12)
        .padding(.bottom, 7)
    }

    @ViewBuilder
    private var content: some View {
        if store.items.isEmpty {
            EmptyKeyboardState(icon: "clipboard", title: "暂无历史")
        } else if displayedItems.isEmpty {
            EmptyKeyboardState(icon: "magnifyingglass", title: "无匹配结果")
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(displayedItems) { item in
                        Button {
                            handleSelection(item)
                        } label: {
                            ClipKeyboardCard(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button(action: onDismiss) {
                Image(systemName: "globe")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(notice ?? "\(displayedItems.count) 条")
                .font(.system(size: 12, weight: notice == nil ? .regular : .semibold))
                .foregroundStyle(notice == nil ? .secondary : .primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)

            Button(action: onDeleteBackward) {
                Image(systemName: "delete.left")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
    }

    private func handleSelection(_ item: ClipItem) {
        let didComplete = onSelect(item)
        showNotice(didComplete ? successMessage(for: item) : "复制失败")
    }

    private func successMessage(for item: ClipItem) -> String {
        switch item.kind {
        case .text:
            return "已输入"
        case .image:
            return "图片已复制"
        case .file:
            return "文件已复制"
        }
    }

    private func showNotice(_ text: String) {
        noticeTask?.cancel()
        withAnimation(.easeInOut(duration: 0.15)) {
            notice = text
        }
        noticeTask = Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.15)) {
                    notice = nil
                }
            }
        }
    }
}

private enum ClipFilter: String, CaseIterable, Identifiable {
    case all
    case text
    case image
    case file

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .text: return "文本"
        case .image: return "图片"
        case .file: return "文件"
        }
    }

    func matches(_ item: ClipItem) -> Bool {
        switch self {
        case .all:
            return true
        case .text:
            return item.kind == .text
        case .image:
            return item.kind == .image
        case .file:
            return item.kind == .file
        }
    }
}

private struct EmptyKeyboardState: View {
    let icon: String
    let title: String

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ClipKeyboardCard: View {
    let item: ClipItem

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                TypeBadge(kind: item.kind)
                Spacer(minLength: 4)
                Text(item.updatedAt.relativeString)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            switch item.kind {
            case .text:
                textPreview
            case .image:
                imagePreview
            case .file:
                filePreview
            }
        }
        .padding(10)
        .frame(width: 154, height: 118)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(borderColor, lineWidth: item.isPinned ? 1 : 0.5)
        }
    }

    private var textPreview: some View {
        Text(item.content)
            .lineLimit(5)
            .font(.system(size: 12.5))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var imagePreview: some View {
        ZStack {
            if let image = item.thumbnailImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.secondarySystemFill), in: RoundedRectangle(cornerRadius: 6))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var filePreview: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: item.fileIcon)
                .font(.system(size: 25, weight: .light))
                .foregroundStyle(item.kindColor)
                .frame(width: 32, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .lineLimit(2)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(item.byteCount.byteCountString)
                    .lineLimit(1)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var cardBackground: Color {
        item.isPinned
            ? Color(UIColor.systemYellow).opacity(0.13)
            : Color(UIColor.secondarySystemGroupedBackground)
    }

    private var borderColor: Color {
        item.isPinned ? .yellow.opacity(0.8) : Color(UIColor.separator).opacity(0.55)
    }
}

private struct TypeBadge: View {
    let kind: ClipKind

    var body: some View {
        Label(kind.title, systemImage: kind.icon)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(kind.color)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(kind.color.opacity(0.12), in: Capsule())
    }
}

private extension ClipItem {
    var thumbnailImage: UIImage? {
        guard let url = ClipStore.shared.thumbnailURL(for: self) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    var kindColor: Color {
        kind.color
    }

    var fileIcon: String {
        if let typeIdentifier,
           typeIdentifier.contains("pdf") {
            return "doc.richtext"
        }
        return "doc"
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

    var color: Color {
        switch self {
        case .text: return .blue
        case .image: return .green
        case .file: return .orange
        }
    }
}

private extension Optional where Wrapped == Int {
    var byteCountString: String {
        guard let self else { return "未知大小" }
        return ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .file)
    }
}

private extension Date {
    var relativeString: String {
        let diff = Int(Date.now.timeIntervalSince(self))
        if diff < 60 { return "\(max(0, diff))秒前" }
        if diff < 3600 { return "\(diff / 60)分前" }
        if diff < 86400 { return "\(diff / 3600)小时前" }
        return "\(diff / 86400)天前"
    }
}
