import SwiftUI
import ClipKeepCore

struct FavoritesView: View {
    @ObservedObject var vm: ClipListViewModel
    @State private var showPicker = false
    @State private var renamingCategory: String? = nil
    @State private var renameText = ""
    @State private var showCopiedToast = false
    @State private var toastTimer: Timer?

    // MARK: – Group model

    private struct CategoryGroup: Identifiable {
        let category: String?
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

        var result = categories.map { cat in
            CategoryGroup(category: cat, items: pinned.filter { $0.pinnedCategory == cat })
        }
        let uncategorized = pinned.filter { $0.pinnedCategory == nil }
        if !uncategorized.isEmpty {
            result.append(CategoryGroup(category: nil, items: uncategorized))
        }
        return result
    }

    // MARK: – Body

    var body: some View {
        NavigationStack {
            Group {
                if grouped.isEmpty { emptyState } else { list }
            }
            .navigationTitle("收藏")
            .onAppear { vm.reload() }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showPicker = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showPicker, onDismiss: { vm.reload() }) {
                AddFavoriteSheet(allItems: vm.items, existingCategories: allCategories())
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
            Menu("移动到…") {
                Button("未分类") {
                    ClipStore.shared.setCategory(id: item.id, category: nil)
                    vm.reload()
                }
                ForEach(allCategories().filter { $0 != category }, id: \.self) { cat in
                    Button(cat) {
                        ClipStore.shared.setCategory(id: item.id, category: cat)
                        vm.reload()
                    }
                }
            }
            Button { copyItem(item) } label: {
                Label("复制", systemImage: "doc.on.doc")
            }
            Divider()
            Button(role: .destructive) {
                ClipStore.shared.togglePin(id: item.id)
                vm.reload()
            } label: {
                Label("取消收藏", systemImage: "star.slash")
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                ClipStore.shared.togglePin(id: item.id)
                vm.reload()
            } label: {
                Label("取消收藏", systemImage: "star.slash")
            }
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
        VStack(spacing: 16) {
            Image(systemName: "star.circle")
                .font(.system(size: 52, weight: .ultraLight))
                .foregroundStyle(.tertiary)
            Text("还没有收藏")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("点击右上角 + 从历史记录中添加")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Button {
                showPicker = true
            } label: {
                Label("添加收藏", systemImage: "plus")
                    .font(.system(size: 15, weight: .medium))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.white)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 40)
    }

    // MARK: – Helpers

    private func allCategories() -> [String] {
        vm.items.filter(\.isPinned).compactMap(\.pinnedCategory)
            .reduce(into: [String]()) { r, c in if !r.contains(c) { r.append(c) } }
            .sorted()
    }

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
        for item in items { ClipStore.shared.setCategory(id: item.id, category: new) }
        vm.reload()
    }
}

// MARK: – Add Favorite Sheet

private struct AddFavoriteSheet: View {
    let allItems: [ClipItem]
    let existingCategories: [String]

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selected: Set<UUID> = []
    @State private var category: String = ""
    @State private var showNewCategory = false
    @State private var newCategory = ""

    private var candidates: [ClipItem] {
        // Show unpinned items (already-pinned ones can be managed in the list)
        let base = allItems.filter { !$0.isPinned }
        guard !searchText.isEmpty else { return base }
        return base.filter { $0.searchableText.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Category selector
                categoryBar
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(UIColor.secondarySystemBackground))

                Divider()

                // Items list
                if candidates.isEmpty {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: allItems.filter { !$0.isPinned }.isEmpty
                              ? "checkmark.circle" : "magnifyingglass")
                            .font(.system(size: 32, weight: .ultraLight))
                            .foregroundStyle(.tertiary)
                        Text(allItems.filter { !$0.isPinned }.isEmpty
                             ? "所有条目都已收藏" : "无匹配结果")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                } else {
                    List(candidates) { item in
                        HStack(spacing: 12) {
                            Image(systemName: selected.contains(item.id)
                                  ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20))
                                .foregroundStyle(selected.contains(item.id)
                                                 ? Color.accentColor : Color.secondary)
                                .animation(.easeInOut(duration: 0.15), value: selected.contains(item.id))

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
                        .onTapGesture {
                            if selected.contains(item.id) {
                                selected.remove(item.id)
                            } else {
                                selected.insert(item.id)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .searchable(text: $searchText, prompt: "搜索历史记录")
            .navigationTitle("添加收藏")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("收藏 (\(selected.count))") {
                        let cat = category.isEmpty ? nil : category
                        for id in selected {
                            ClipStore.shared.pin(id: id, category: cat)
                        }
                        dismiss()
                    }
                    .disabled(selected.isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var categoryBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("收藏到分类")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    // "不分类"
                    categoryChip(title: "不分类", value: "")
                    // Existing categories
                    ForEach(existingCategories, id: \.self) { cat in
                        categoryChip(title: cat, value: cat)
                    }
                    // New category
                    Button {
                        showNewCategory = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus").font(.system(size: 10))
                            Text("新建").font(.system(size: 12))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(Color(UIColor.secondarySystemFill), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .alert("新建分类", isPresented: $showNewCategory) {
                        TextField("分类名称", text: $newCategory)
                        Button("确定") {
                            if !newCategory.isEmpty {
                                category = newCategory
                                newCategory = ""
                            }
                        }
                        Button("取消", role: .cancel) { newCategory = "" }
                    }
                }
            }
        }
    }

    private func categoryChip(title: String, value: String) -> some View {
        let isSelected = category == value
        return Button {
            category = value
        } label: {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(
                    isSelected ? Color.accentColor.opacity(0.12) : Color(UIColor.secondarySystemFill),
                    in: Capsule()
                )
                .overlay(Capsule().strokeBorder(
                    isSelected ? Color.accentColor.opacity(0.3) : Color.clear,
                    lineWidth: 0.5
                ))
        }
        .buttonStyle(.plain)
    }
}
