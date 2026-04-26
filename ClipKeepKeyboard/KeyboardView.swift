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
    @State private var pendingPinItem: ClipItem?   // non-nil = category picker visible

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
            topBar           // search + filter chips — 44 pt
            Divider().opacity(0.4)
            content          // cards — flex
            Divider().opacity(0.4)
            toolbar          // globe / status / delete — 44 pt
        }
        .background(Color(UIColor.systemBackground))
        .onDisappear { noticeTask?.cancel() }
        .overlay(alignment: .bottom) {
            if let item = pendingPinItem {
                CategoryPickerOverlay(
                    item: item,
                    existingCategories: ClipStore.shared.allPinnedCategories()
                ) { category in
                    ClipStore.shared.pin(id: item.id, category: category)
                    store.reload()
                    showNotice(category.map { "已收藏到「\($0)」" } ?? "已收藏")
                    pendingPinItem = nil
                } onCancel: {
                    pendingPinItem = nil
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: pendingPinItem == nil)
    }

    // MARK: – Top bar (search left, filter chips right)

    private var topBar: some View {
        HStack(spacing: 8) {
            // Search field
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                TextField("搜索", text: $searchText)
                    .font(.system(size: 13))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(Color(UIColor.secondarySystemFill), in: RoundedRectangle(cornerRadius: 8))
            .frame(maxWidth: 140)

            // Filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(ClipFilter.allCases) { filter in
                        FilterChip(
                            title: filter.title,
                            icon: filter.icon,
                            isSelected: selectedFilter == filter
                        ) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedFilter = filter
                            }
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
    }

    // MARK: – Content

    @ViewBuilder
    private var content: some View {
        if store.items.isEmpty {
            EmptyKeyboardState(icon: "clipboard", title: "暂无历史",
                               subtitle: "请在系统设置中开启「允许完全访问」")
        } else if displayedItems.isEmpty {
            EmptyKeyboardState(icon: "magnifyingglass", title: "无匹配结果")
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(displayedItems) { item in
                        ClipKeyboardCard(item: item) {
                            handleSelection(item)
                        } onPin: {
                            if item.isPinned {
                                // already pinned → unpin
                                ClipStore.shared.togglePin(id: item.id)
                                store.reload()
                                showNotice("已取消收藏")
                            } else {
                                // not pinned → show category picker
                                withAnimation { pendingPinItem = item }
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
            }
        }
    }

    // MARK: – Toolbar

    private var toolbar: some View {
        HStack(spacing: 4) {
            Button(action: onDismiss) {
                Image(systemName: "globe")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            if let notice {
                Text(notice)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else {
                Text("\(displayedItems.count) 条")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .transition(.opacity)
            }

            Spacer()

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
        .animation(.easeInOut(duration: 0.15), value: notice)
    }

    // MARK: – Helpers

    private func handleSelection(_ item: ClipItem) {
        let ok = onSelect(item)
        showNotice(ok ? (item.kind == .text ? "已输入" : "已复制") : "操作失败")
    }

    private func showNotice(_ text: String) {
        noticeTask?.cancel()
        notice = text
        noticeTask = Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { notice = nil }
        }
    }
}

// MARK: – Filter model

private enum ClipFilter: String, CaseIterable, Identifiable {
    case all, pinned, text, image, file
    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:    return "全部"
        case .pinned: return "收藏"
        case .text:   return "文本"
        case .image:  return "图片"
        case .file:   return "文件"
        }
    }

    var icon: String {
        switch self {
        case .all:    return "tray.full"
        case .pinned: return "star.fill"
        case .text:   return "text.alignleft"
        case .image:  return "photo"
        case .file:   return "doc"
        }
    }

    func matches(_ item: ClipItem) -> Bool {
        switch self {
        case .all:    return true
        case .pinned: return item.isPinned
        case .text:   return item.kind == .text
        case .image:  return item.kind == .image
        case .file:   return item.kind == .file
        }
    }
}

// MARK: – Filter chip

private struct FilterChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .medium))
                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.12)
                    : Color(UIColor.secondarySystemFill),
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.3) : .clear, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: – Card

private struct ClipKeyboardCard: View {
    let item: ClipItem
    let onTap: () -> Void
    let onPin: () -> Void

    @State private var pressed = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                // Header row: type badge + pin star + time
                HStack(spacing: 4) {
                    TypeBadge(kind: item.kind)
                    if item.isPinned {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.yellow)
                    }
                    Spacer(minLength: 0)
                    Text(item.updatedAt.relativeString)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .padding(.bottom, 7)

                // Content preview
                switch item.kind {
                case .text:
                    Text(item.content)
                        .lineLimit(5)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                case .image:
                    ImagePreview(store: ClipStore.shared, item: item)
                case .file:
                    FilePreview(item: item)
                }
            }
            .padding(10)
            .frame(width: 148, height: 112)
            .background(
                item.isPinned
                    ? Color.yellow.opacity(0.08)
                    : Color(UIColor.secondarySystemGroupedBackground)
            )
            .clipShape(RoundedRectangle(cornerRadius: 13))
            .overlay(
                RoundedRectangle(cornerRadius: 13)
                    .strokeBorder(
                        item.isPinned
                            ? Color.yellow.opacity(0.4)
                            : Color(UIColor.separator).opacity(0.5),
                        lineWidth: 0.5
                    )
            )
            .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
            .scaleEffect(pressed ? 0.95 : 1)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in onPin() }
        )
        ._onButtonGesture(pressing: { p in
            withAnimation(.easeInOut(duration: 0.1)) { pressed = p }
        }, perform: {})
    }
}

// MARK: – Type badge

private struct TypeBadge: View {
    let kind: ClipKind

    var body: some View {
        Label(label, systemImage: icon)
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var label: String {
        switch kind {
        case .text:  return "文本"
        case .image: return "图片"
        case .file:  return "文件"
        }
    }
    private var icon: String {
        switch kind {
        case .text:  return "text.alignleft"
        case .image: return "photo"
        case .file:  return "doc"
        }
    }
    private var color: Color {
        switch kind {
        case .text:  return .secondary
        case .image: return .blue
        case .file:  return .orange
        }
    }
}

// MARK: – Image preview

private struct ImagePreview: View {
    let store: ClipStore
    let item: ClipItem

    var body: some View {
        Group {
            if let url = store.thumbnailURL(for: item) ?? store.assetURL(for: item),
               let uiImage = UIImage(contentsOfFile: url.path) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: "photo")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: – File preview

private struct FilePreview: View {
    let item: ClipItem

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: "doc.fill")
                .font(.system(size: 24))
                .foregroundStyle(.orange.opacity(0.8))
            Text(item.fileName ?? item.content)
                .lineLimit(3)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: – Empty state

private struct EmptyKeyboardState: View {
    let icon: String
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .ultraLight))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: – Category picker overlay

private struct CategoryPickerOverlay: View {
    let item: ClipItem
    let existingCategories: [String]
    let onConfirm: (String?) -> Void
    let onCancel: () -> Void

    @State private var selected: String? = nil
    @State private var customText = ""
    @State private var showCustomField = false

    private let suggestions = ["工作", "个人", "常用", "灵感"]

    var allChips: [String] {
        var result = existingCategories
        for s in suggestions where !result.contains(s) { result.append(s) }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            VStack(spacing: 10) {
                // Title row
                HStack {
                    Button("取消", action: onCancel)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("收藏到…")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Button {
                        onConfirm(showCustomField && !customText.isEmpty ? customText : selected)
                    } label: {
                        Text("确定")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .padding(.horizontal, 16)

                // Category chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        // "不分类"
                        chip(title: "不分类", icon: "star", isSelected: selected == nil && !showCustomField) {
                            selected = nil; showCustomField = false
                        }
                        ForEach(allChips, id: \.self) { cat in
                            chip(title: cat, icon: nil, isSelected: selected == cat && !showCustomField) {
                                selected = cat; showCustomField = false
                            }
                        }
                        // "新建"
                        chip(title: "新建…", icon: "plus", isSelected: showCustomField) {
                            showCustomField = true; selected = nil
                        }
                    }
                    .padding(.horizontal, 12)
                }

                // Custom name input
                if showCustomField {
                    HStack(spacing: 6) {
                        TextField("分类名称", text: $customText)
                            .font(.system(size: 13))
                            .autocorrectionDisabled()
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Color(UIColor.secondarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .padding(.horizontal, 12)
                }
            }
            .padding(.vertical, 10)
            .background(Color(UIColor.systemBackground))
        }
    }

    private func chip(title: String, icon: String?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon).font(.system(size: 10)) }
                Text(title).font(.system(size: 12, weight: isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                isSelected ? Color.accentColor.opacity(0.12) : Color(UIColor.secondarySystemFill),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: – Date helper

private extension Date {
    var relativeString: String {
        let diff = Int(Date.now.timeIntervalSince(self))
        if diff < 60    { return "\(diff)秒前" }
        if diff < 3600  { return "\(diff / 60)分前" }
        if diff < 86400 { return "\(diff / 3600)小时前" }
        return "\(diff / 86400)天前"
    }
}
