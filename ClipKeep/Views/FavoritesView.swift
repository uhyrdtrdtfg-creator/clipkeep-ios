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

    // Stable identifiable group — avoids nil-ID bug in ForEach
    private struct CategoryGroup: Identifiable {
        let category: String?          // nil = 未分类
        let items: [ClipItem]
        var id: String { category ?? "__uncategorized__" }
        var displayName: String { category ?? "未分类" }
    }

    private var grouped: [CategoryGroup] {
        let pinned = vm.items.filter { $0.isPinned }
        guard !pinned.isEmpty else { return [] }

        let categories = pinned.compactMap { $0.pinnedCategory }
            .reduce(into: [String]()) { r, c in if !r.contains(c) { r.append(c) } }
            .sorted()

        var result: [CategoryGroup] = categories.map { cat in
            CategoryGroup(category: cat, items: pinned.filter { $0.pinnedCategory == cat })
        }
        let uncategorized = pinned.filter { $0.pinnedCategory == nil }
        if !uncategorized.isEmpty {
            result.append(CategoryGroup(category: nil, items: uncategorized))
        }
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
            .onAppear { vm.reload() }
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
            ForEach(grouped) { group in
                Section {
                    ForEach(group.items) { item in
                        itemRow(item, inCategory: group.category)
                    }
                } header: {
                    categoryHeader(group)
                }
            }
        }
        .listStyle(.insetGrouped)
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

    private func categoryHeader(_ group: CategoryGroup) -> some View {
        HStack {
            Image(systemName: group.category == nil ? "tray" : "folder.fill")
                .font(.system(size: 11))
                .foregroundStyle(group.category == nil ? Color.secondary : Color.accentColor)
            Text(group.displayName)
                .font(.system(size: 12, weight: .semibold))
            Text("(\(group.items.count))")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Spacer()
            if let category = group.category {
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

}
