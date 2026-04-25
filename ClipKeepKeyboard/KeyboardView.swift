import SwiftUI
import ClipKeepCore

struct KeyboardView: View {
    @ObservedObject var store: KeyboardStore
    let proxy: UITextDocumentProxy
    let onDismiss: () -> Void

    @State private var searchText = ""
    @State private var isSearching = false

    private var displayedItems: [ClipItem] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return Array(store.items.prefix(50)) }
        return store.items.filter { $0.content.localizedCaseInsensitiveContains(q) }.prefix(50).map { $0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ──────────────────────────────────────────────
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("剪贴板")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer()
                // Search toggle
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isSearching.toggle()
                        if !isSearching { searchText = "" }
                    }
                } label: {
                    Image(systemName: isSearching ? "xmark.circle.fill" : "magnifyingglass")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 6)

            // ── Search bar (animated) ────────────────────────────────
            if isSearching {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    TextField("搜索", text: $searchText)
                        .font(.callout)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(UIColor.systemFill), in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            Divider()

            // ── Card grid / empty state ──────────────────────────────
            if store.items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "clipboard")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("暂无历史记录")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("请确认已开启「允许完全访问」")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isSearching {
                // Search results as compact list
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(displayedItems) { item in
                            Button {
                                proxy.insertText(item.content)
                            } label: {
                                HStack {
                                    Text(item.content)
                                        .lineLimit(2)
                                        .font(.callout)
                                        .foregroundStyle(.primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(item.updatedAt.relativeString)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)
                            Divider().padding(.leading, 14)
                        }
                    }
                }
            } else {
                // Card scroll view
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(displayedItems) { item in
                            ClipCard(item: item) {
                                proxy.insertText(item.content)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
            }

            Divider()

            // ── Bottom toolbar ───────────────────────────────────────
            HStack {
                Button(action: onDismiss) {
                    Image(systemName: "globe")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .padding(8)
                }
                Spacer()
                Button {
                    proxy.deleteBackward()
                } label: {
                    Image(systemName: "delete.left")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .padding(8)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 44)
        }
        .background(Color(UIColor.systemGroupedBackground))
    }
}

// MARK: - Card

private struct ClipCard: View {
    let item: ClipItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                // Type badge + time
                HStack {
                    Label("文本", systemImage: "text.alignleft")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(item.updatedAt.relativeString)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                // Content preview
                Text(item.content)
                    .lineLimit(4)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(10)
            .frame(width: 148, height: 110)
            .background(Color(UIColor.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color(UIColor.separator), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Date helper

private extension Date {
    var relativeString: String {
        let diff = Int(Date.now.timeIntervalSince(self))
        if diff < 60  { return "\(diff)秒前" }
        if diff < 3600 { return "\(diff / 60)分前" }
        if diff < 86400 { return "\(diff / 3600)小时前" }
        return "\(diff / 86400)天前"
    }
}
