import SwiftUI
import UIKit
import Vision
import ClipKeepCore

struct KeyboardView: View {
    @ObservedObject var store: KeyboardStore
    let onSelect: (ClipItem) -> Bool
    let onInsertText: (String) -> Void   // used to push OCR-recognised text into the host field
    let onUndoInsertion: () -> Bool
    let onDeleteBackward: () -> Void
    let onDismiss: () -> Void

    @State private var searchText = ""
    @State private var selectedFilter: ClipFilter = .all
    @State private var selectedHistoryIndex = 0
    @State private var notice: String?
    @State private var noticeTask: Task<Void, Never>?
    @State private var pendingPinItem: ClipItem?          // non-nil = category picker visible
    @State private var pendingImageActionItem: ClipItem?  // non-nil = image action overlay visible

    /// Static filters + one chip per pinned category (inserted after .pinned)
    private var allFilters: [ClipFilter] {
        let cats = store.pinnedCategories.map { ClipFilter.category($0) }
        var result = ClipFilter.staticFilters
        if let idx = result.firstIndex(of: .pinned) {
            result.insert(contentsOf: cats, at: result.index(after: idx))
        }
        return result
    }

    private var displayedItems: [ClipItem] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.items
            .filter { selectedFilter.matches($0) }
            .filter { q.isEmpty || $0.searchableText.localizedCaseInsensitiveContains(q) }
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
                return lhs.createdAt > rhs.createdAt
            }
            .prefix(50)
            .map { $0 }
    }

    private var shortcutItems: [ClipItem] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.items
            .filter { $0.isPinned }
            .filter { q.isEmpty || $0.searchableText.localizedCaseInsensitiveContains(q) }
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
                return lhs.createdAt > rhs.createdAt
            }
            .prefix(12)
            .map { $0 }
    }

    private var displayedItemIDs: [UUID] {
        displayedItems.map(\.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            content
            toolbar
        }
        .background(Color(UIColor.systemGroupedBackground))
        .onDisappear { noticeTask?.cancel() }
        .overlay(alignment: .bottom) {
            // Image action overlay takes priority; category picker is shown after "收藏" is chosen.
            if let item = pendingImageActionItem {
                ImageActionOverlay(
                    item: item,
                    onOCR: {
                        playSelectionHaptic()
                        pendingImageActionItem = nil
                        Task { await performOCR(item) }
                    },
                    onPin: {
                        playSelectionHaptic()
                        pendingImageActionItem = nil
                        if item.isPinned {
                            ClipStore.shared.togglePin(id: item.id)
                            store.reload()
                            showNotice("已取消收藏")
                        } else {
                            withAnimation { pendingPinItem = item }
                        }
                    },
                    onCancel: {
                        withAnimation { pendingImageActionItem = nil }
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let item = pendingPinItem {
                CategoryPickerOverlay(
                    item: item,
                    existingCategories: ClipStore.shared.allPinnedCategories()
                ) { category in
                    ClipStore.shared.pin(id: item.id, category: category)
                    store.reload()
                    playImpactHaptic()
                    showNotice(category.map { "已收藏到「\($0)」" } ?? "已收藏")
                    pendingPinItem = nil
                } onCancel: {
                    playSelectionHaptic()
                    pendingPinItem = nil
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottom) {
            if pendingPinItem == nil, pendingImageActionItem == nil {
                noticeToast
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: pendingPinItem == nil)
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: pendingImageActionItem == nil)
        .onChange(of: displayedItemIDs) { ids in
            selectedHistoryIndex = min(selectedHistoryIndex, max(0, ids.count - 1))
        }
    }

    // MARK: – Top bar

    private var topBar: some View {
        HStack(spacing: 8) {
            searchField
                .frame(maxWidth: 138)
            filterBar
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(height: 50)
        .background(Color(UIColor.systemBackground))
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)

            TextField("搜索", text: $searchText)
                .font(.system(size: 13))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(UIColor.separator).opacity(0.35), lineWidth: 0.5)
        )
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(allFilters) { filter in
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
            .padding(.horizontal, 1)
        }
        .frame(height: 32)
    }

    // MARK: – Content

    @ViewBuilder
    private var content: some View {
        if store.items.isEmpty {
            EmptyKeyboardState(icon: "clipboard", title: "暂无历史",
                               subtitle: "请在系统设置中开启「允许完全访问」")
        } else if displayedItems.isEmpty && shortcutItems.isEmpty {
            EmptyKeyboardState(icon: "magnifyingglass", title: "无匹配结果")
        } else {
            VStack(spacing: 0) {
                if !shortcutItems.isEmpty {
                    ShortcutStrip(items: shortcutItems) { item in
                        handleSelection(item)
                    }
                }

                historyPager
            }
            .background(Color(UIColor.systemGroupedBackground))
        }
    }

    @ViewBuilder
    private var historyPager: some View {
        if displayedItems.isEmpty {
            EmptyKeyboardState(icon: "magnifyingglass", title: "无匹配结果")
        } else {
            GeometryReader { proxy in
                let cardHeight = max(88, proxy.size.height - 16)
                let cardWidth = max(176, proxy.size.width - 20)
                let indexedItems = Array(displayedItems.enumerated())

                TabView(selection: $selectedHistoryIndex) {
                    ForEach(indexedItems, id: \.element.id) { index, item in
                        ClipHistoryCard(item: item, width: cardWidth, height: cardHeight) {
                            handleSelection(item)
                        } onPin: {
                            handlePin(item)
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(width: proxy.size.width, height: proxy.size.height)
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

            Button {
                handleUndoInsertion()
            } label: {
                Label(undoTitle, systemImage: "arrow.uturn.backward")
                    .font(.system(size: 13, weight: .semibold))
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(store.canUndoInsertion ? Color.accentColor : Color.secondary)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(
                        store.canUndoInsertion
                            ? Color.accentColor.opacity(0.12)
                            : Color(UIColor.secondarySystemFill),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
            }
            .buttonStyle(.plain)
            .opacity(store.canUndoInsertion ? 1 : 0.45)

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
        .frame(height: 42)
        .background(Color(UIColor.systemBackground))
        .animation(.easeInOut(duration: 0.15), value: notice)
        .animation(.easeInOut(duration: 0.15), value: store.canUndoInsertion)
    }

    @ViewBuilder
    private var noticeToast: some View {
        if let notice {
            Text(notice)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color(UIColor.separator).opacity(0.25), lineWidth: 0.5)
                )
                .padding(.bottom, 48)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private var undoTitle: String {
        store.undoInsertionCount > 1 ? "撤回 \(store.undoInsertionCount)" : "撤回"
    }

    // MARK: – Helpers

    private func handleSelection(_ item: ClipItem) {
        let ok = onSelect(item)
        showNotice(ok ? (item.kind == .text ? "已输入" : "已复制") : "操作失败")
    }

    private func handleUndoInsertion() {
        showNotice(onUndoInsertion() ? "已撤回" : "无可撤回")
    }

    private func handlePin(_ item: ClipItem) {
        playSelectionHaptic()
        if item.kind == .image {
            withAnimation { pendingImageActionItem = item }
        } else if item.isPinned {
            ClipStore.shared.togglePin(id: item.id)
            store.reload()
            showNotice("已取消收藏")
        } else {
            withAnimation { pendingPinItem = item }
        }
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

    private func playSelectionHaptic() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func playImpactHaptic() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Run Vision OCR on an image item and insert the recognised text into the host field.
    /// Uses the cached `recognizedText` when available to avoid redundant CPU work.
    private func performOCR(_ item: ClipItem) async {
        // Fast path: use cached OCR result stored during a previous recognition.
        if let cached = item.recognizedText, !cached.isEmpty {
            onInsertText(cached)
            showNotice("已输入识别文字")
            return
        }

        guard let url = ClipStore.shared.assetURL(for: item),
              let uiImage = UIImage(contentsOfFile: url.path),
              let cgImage = uiImage.cgImage else {
            showNotice("无法读取图片")
            return
        }

        showNotice("识别中…")

        // Vision OCR is CPU-intensive — run detached so we don't stall the main actor.
        let text = await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            // Priority order: Simplified/Traditional Chinese, English, Japanese.
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US", "ja-JP"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])

            return (request.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
        }.value

        if text.isEmpty {
            showNotice("未识别到文字")
        } else {
            onInsertText(text)
            showNotice("已输入识别文字")
            // Persist so next long-press on the same image is instant.
            ClipStore.shared.saveRecognizedText(id: item.id, text: text)
        }
    }
}

// MARK: – Filter model

private enum ClipFilter: Equatable, Identifiable {
    case all
    case category(String)   // specific pinned category
    case pinned             // all pinned (no category set)
    case text
    case image
    case file

    var id: String {
        switch self {
        case .all:             return "all"
        case .category(let c): return "cat_\(c)"
        case .pinned:          return "pinned"
        case .text:            return "text"
        case .image:           return "image"
        case .file:            return "file"
        }
    }

    var title: String {
        switch self {
        case .all:             return "全部"
        case .category(let c): return c
        case .pinned:          return "收藏"
        case .text:            return "文本"
        case .image:           return "图片"
        case .file:            return "文件"
        }
    }

    var icon: String {
        switch self {
        case .all:             return "tray.full"
        case .category:        return "folder.fill"
        case .pinned:          return "star.fill"
        case .text:            return "text.alignleft"
        case .image:           return "photo"
        case .file:            return "doc"
        }
    }

    func matches(_ item: ClipItem) -> Bool {
        switch self {
        case .all:             return true
        case .category(let c): return item.isPinned && item.pinnedCategory == c
        case .pinned:          return item.isPinned
        case .text:            return item.kind == .text
        case .image:           return item.kind == .image
        case .file:            return item.kind == .file
        }
    }

    /// Static chips always shown; category chips are inserted dynamically.
    static let staticFilters: [ClipFilter] = [.all, .pinned, .text, .image, .file]
}

// MARK: – Filter chip

private struct FilterChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    private var showsTitle: Bool {
        isSelected || icon == "folder.fill"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 14)

                if showsTitle {
                    Text(title)
                        .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 88)
                }
            }
            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            .padding(.horizontal, showsTitle ? 9 : 0)
            .frame(width: showsTitle ? nil : 34, height: 32)
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.12)
                    : Color(UIColor.secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.35) : Color(UIColor.separator).opacity(0.25),
                        lineWidth: 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

// MARK: – Shortcuts

private struct ShortcutStrip: View {
    let items: [ClipItem]
    let onSelect: (ClipItem) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items) { item in
                    ShortcutChip(item: item) {
                        onSelect(item)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
        .frame(height: 48)
        .background(Color(UIColor.systemBackground))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

private struct ShortcutChip: View {
    let item: ClipItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: item.kind.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(item.kind.tint)
                    .frame(width: 14)

                Text(item.shortcutTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 128)

                Image(systemName: "star.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.yellow)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(Color(UIColor.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color(UIColor.separator).opacity(0.28), lineWidth: 0.5)
            )
        }
        .buttonStyle(KeyboardRowButtonStyle())
        .accessibilityLabel(item.keyboardTitle)
    }
}

// MARK: – History card

private struct ClipHistoryCard: View {
    let item: ClipItem
    let width: CGFloat
    let height: CGFloat
    let onTap: () -> Void
    let onPin: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onTap) {
                cardContent
                    .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(KeyboardRowButtonStyle())
            .frame(width: width, height: height)

            Button(action: onPin) {
                Image(systemName: actionIcon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(actionTint)
                    .frame(width: 34, height: 34)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color(UIColor.separator).opacity(0.24), lineWidth: 0.5)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(KeyboardRowButtonStyle())
            .accessibilityLabel(actionAccessibilityLabel)
            .padding(8)
        }
        .frame(width: width, height: height)
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: isCompact ? 6 : 8) {
            HStack(spacing: 5) {
                KindMeta(kind: item.kind)
                Text(item.updatedAt.relativeString)
                Spacer(minLength: 28)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)

            HStack(alignment: .top, spacing: isCompact ? 8 : 10) {
                ClipPreview(item: item, size: previewSize)

                VStack(alignment: .leading, spacing: 5) {
                    Text(item.keyboardTitle)
                        .font(.system(size: isCompact ? 13 : 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(isCompact ? 2 : 3)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if !isCompact, let detail = item.keyboardDetail {
                        Text(detail)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Image(systemName: item.kind == .text ? "return" : "doc.on.clipboard")
                    .font(.system(size: 11, weight: .semibold))
                Text(item.kind == .text ? "输入" : "复制")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                if item.isPinned {
                    Image(systemName: "star.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.yellow)
                }
            }
            .foregroundStyle(.tertiary)
            .lineLimit(1)
        }
        .padding(isCompact ? 10 : 12)
        .frame(width: width, height: height, alignment: .leading)
        .background(
            item.isPinned
                ? Color.yellow.opacity(0.08)
                : Color(UIColor.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    item.isPinned
                        ? Color.yellow.opacity(0.35)
                        : Color(UIColor.separator).opacity(0.32),
                    lineWidth: 0.5
                )
        )
    }

    private var isCompact: Bool {
        height < 118
    }

    private var previewSize: CGFloat {
        isCompact ? 40 : 52
    }

    private var actionIcon: String {
        if item.kind == .image && !item.isPinned { return "ellipsis.circle.fill" }
        return item.isPinned ? "star.fill" : "star"
    }

    private var actionTint: Color {
        item.isPinned ? .yellow : .secondary
    }

    private var actionAccessibilityLabel: String {
        if item.kind == .image && !item.isPinned { return "图片操作" }
        return item.isPinned ? "取消收藏" : "收藏"
    }
}

private struct KeyboardRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct KindMeta: View {
    let kind: ClipKind

    var body: some View {
        Label(kind.label, systemImage: kind.icon)
            .labelStyle(.titleAndIcon)
            .foregroundStyle(kind.tint)
    }
}

// MARK: – Preview

private struct ClipPreview: View {
    let item: ClipItem
    var size: CGFloat = 42

    var body: some View {
        ZStack {
            switch item.kind {
            case .image:
                imageContent
            case .text:
                iconContent(systemName: "text.alignleft")
            case .file:
                fileContent
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var imageContent: some View {
        if let url = ClipStore.shared.thumbnailURL(for: item) ?? ClipStore.shared.assetURL(for: item),
           let uiImage = UIImage(contentsOfFile: url.path) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
        } else {
            iconContent(systemName: "photo")
        }
    }

    private var fileContent: some View {
        ZStack(alignment: .bottomTrailing) {
            iconContent(systemName: "doc.fill")
            if let ext = item.fileExtensionLabel {
                Text(ext)
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 3)
                    .frame(height: 13)
                    .background(item.kind.tint, in: RoundedRectangle(cornerRadius: 4))
                    .padding(max(2, size * 0.07))
            }
        }
    }

    private func iconContent(systemName: String) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(item.kind.tint.opacity(0.12))
            .overlay(
                Image(systemName: systemName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(item.kind.tint)
            )
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

// MARK: – Image action overlay

/// Shown when the user long-presses an image card.
/// Lets them choose between OCR-to-input and pinning, without conflating the two actions.
private struct ImageActionOverlay: View {
    let item: ClipItem
    let onOCR: () -> Void
    let onPin: () -> Void
    let onCancel: () -> Void

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
                    Text("图片操作")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    // Balance the cancel button width so the title stays centred.
                    Text("取消")
                        .font(.system(size: 14))
                        .opacity(0)
                }
                .padding(.horizontal, 16)

                HStack(spacing: 10) {
                    // OCR: recognise text and push it straight into the host text field.
                    Button(action: onOCR) {
                        Label("识别文字并输入", systemImage: "text.viewfinder")
                            .font(.system(size: 13, weight: .medium))
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)

                    // Pin / unpin.
                    Button(action: onPin) {
                        Label(
                            item.isPinned ? "取消收藏" : "收藏",
                            systemImage: item.isPinned ? "star.slash.fill" : "star.fill"
                        )
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(Color(UIColor.secondarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
            }
            .padding(.vertical, 10)
            .background(Color(UIColor.systemBackground))
        }
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

private extension ClipItem {
    var keyboardTitle: String {
        switch kind {
        case .text:
            let compact = content
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return compact.isEmpty ? "空文本" : compact
        case .image:
            if let recognizedText, !recognizedText.isEmpty {
                return recognizedText
                    .replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return fileName ?? "图片"
        case .file:
            return fileName ?? content
        }
    }

    var keyboardDetail: String? {
        var parts: [String] = []
        if let pinnedCategory, !pinnedCategory.isEmpty {
            parts.append(pinnedCategory)
        }
        switch kind {
        case .text:
            parts.append("\(content.count)字")
        case .image, .file:
            if let byteCount {
                parts.append(ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file))
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var shortcutTitle: String {
        let title = keyboardTitle
        guard title.count > 18 else { return title }
        return "\(title.prefix(18))…"
    }

    var fileExtensionLabel: String? {
        guard kind == .file else { return nil }
        let ext = URL(fileURLWithPath: fileName ?? content).pathExtension
        guard !ext.isEmpty else { return nil }
        return String(ext.prefix(4)).uppercased()
    }
}

private extension ClipKind {
    var label: String {
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

    var tint: Color {
        switch self {
        case .text: return .blue
        case .image: return .green
        case .file: return .orange
        }
    }
}
