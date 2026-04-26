import SwiftUI
import ClipKeepCore

struct FavoritesView: View {
    @ObservedObject var vm: ClipListViewModel
    @State private var renamingCategory: String? = nil
    @State private var renameText = ""
    @State private var showAddCategory = false
    @State private var newCategoryText = ""
    @State private var showCopiedToast = false
    @State private var toastTimer: Timer?

    // Group pinned items: categories first (sorted), then uncategorized
    private var grouped: [(category: String?, items: [ClipItem])] {
        let pinned = vm.items.filter { $0.isPinned }
        let categories = pinned.compactMap { $0.pinnedCategory }
            .reduce(into: [String]()) { r, c in if !r.contains(c) { r.append(c) } }
            .sorted()
        var result: [(String?, [ClipItem])] = categories.map { cat in
            (cat, pinned.filter { $0.pinnedCategory == cat })
        }
        let uncategorized = pinned.filter { $0.pinnedCategory == nil }
        if !uncategorized.isEmpty { result.append((nil, uncategorized)) }
        return result
    }

    var body: some View {
        NavigationStack {
            Group {
                if grouped.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("收藏")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAddCategory = true } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                }
            }
            .alert("新建分类", isPresented: $showAddCategory) {
                TextField("分类名称", text: $newCategoryText)
                Button("创建") {
                    // Category exists when items are pinned to it; nothing to create now
                    newCategoryText = ""
                }
                Button("取消", role: .cancel) { newCategoryText = "" }
            }
            .alert("重命名分类", isPresented: Binding(
                get: { renamingCategory != nil },
                set: { if !$0 { renamingCategory = nil } }
            )) {
                TextField("新名称", text: $renameText)
                Button("确定") {
                    if let old = renamingCategory, !renameText.isEmpty {
                        renameCategory(from: old, to: renameText)
                    }
                    renamingCategory = nil
                }
                Button("取消", role: .cancel) { renamingCategory = nil }
            }
        }
        .toast(isShowing: $showCopiedToast, message: "已复制")
    }

    // MARK: – List

    private var list: some View {
        List {
            ForEach(grouped, id: \.category) { group in
                Section {
                    ForEach(group.items) { item in
                        itemRow(item, inCategory: group.category)
                    }
                    .onMove { from, to in
                        moveItems(in: group.category, from: from, to: to)
                    }
                } header: {
                    categoryHeader(group.category, count: group.items.count)
                }
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, .constant(.active))
    }

    private func itemRow(_ item: ClipItem, inCategory category: String?) -> some View {
        HStack(spacing: 12) {
            kindIcon(item.kind)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .lineLimit(2)
                    .font(.system(size: 14))
                Text(item.updatedAt.formatted(.relative(presentation: .named)))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture { copyItem(item) }
        .contextMenu {
            // Move to another category
            Menu("移动到…") {
                Button("不分类") { ClipStore.shared.setCategory(id: item.id, category: nil); vm.reload() }
                ForEach(vm.items.filter(\.isPinned).compactMap(\.pinnedCategory)
                    .reduce(into: [String]()) { r, c in if !r.contains(c) { r.append(c) } }
                    .filter { $0 != category }, id: \.self) { cat in
                    Button(cat) { ClipStore.shared.setCategory(id: item.id, category: cat); vm.reload() }
                }
            }
            Button { copyItem(item) } label: { Label("复制", systemImage: "doc.on.doc") }
            Divider()
            Button(role: .destructive) {
                ClipStore.shared.togglePin(id: item.id); vm.reload()
            } label: { Label("取消收藏", systemImage: "star.slash") }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                ClipStore.shared.togglePin(id: item.id); vm.reload()
            } label: { Label("取消收藏", systemImage: "star.slash") }
                .tint(.orange)
        }
    }

    private func categoryHeader(_ category: String?, count: Int) -> some View {
        HStack {
            Image(systemName: category == nil ? "tray" : "folder.fill")
                .font(.system(size: 11))
                .foregroundStyle(category == nil ? Color.secondary : Color.accentColor)
            Text(category ?? "未分类")
                .font(.system(size: 12, weight: .semibold))
            Text("(\(count))")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Spacer()
            if let category {
                Button {
                    renamingCategory = category
                    renameText = category
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "star.circle")
                .font(.system(size: 52, weight: .ultraLight))
                .foregroundStyle(.tertiary)
            Text("还没有收藏")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("在历史列表或键盘中长按条目即可收藏")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    // MARK: – Helpers

    private func kindIcon(_ kind: ClipKind) -> some View {
        let (name, color): (String, Color) = {
            switch kind {
            case .text:  return ("text.alignleft", .secondary)
            case .image: return ("photo", .blue)
            case .file:  return ("doc.fill", .orange)
            }
        }()
        return Image(systemName: name)
            .font(.system(size: 14))
            .foregroundStyle(color)
            .frame(width: 22)
    }

    private func copyItem(_ item: ClipItem) {
        _ = vm.copy(item)
        showCopiedToast = true
        toastTimer?.invalidate()
        toastTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
            Task { @MainActor in showCopiedToast = false }
        }
    }

    private func renameCategory(from old: String, to new: String) {
        let items = ClipStore.shared.load().filter { $0.pinnedCategory == old }
        for item in items {
            ClipStore.shared.setCategory(id: item.id, category: new)
        }
        vm.reload()
    }

    private func moveItems(in category: String?, from source: IndexSet, to destination: Int) {
        // Items within a category are a subset of the full list; reordering is cosmetic only
        // (full reorder support would require persisting explicit order)
    }
}
