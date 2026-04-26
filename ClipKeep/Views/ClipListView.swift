import SwiftUI
import ClipKeepCore

struct ClipListView: View {
    @ObservedObject var vm: ClipListViewModel
    @Environment(\.scenePhase) private var scenePhase

    @State private var showCopiedToast = false
    @State private var showSettings = false
    @State private var toastMessage = "已复制"
    @State private var toastTimer: Timer?
    @State private var detailItem: ClipItem? = nil

    var body: some View {
        NavigationStack {
            List {
                ForEach(vm.displayedItems) { item in
                    ClipRowView(item: item)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // Images and files open a detail view (preview + OCR).
                            // Text items copy immediately — the common case.
                            if item.kind == .image || item.kind == .file {
                                detailItem = item
                            } else {
                                copy(item)
                            }
                        }
                        .contextMenu {
                            Button {
                                copy(item)
                            } label: {
                                Label("复制", systemImage: "doc.on.doc")
                            }
                            if item.kind == .image || item.kind == .file {
                                Button {
                                    detailItem = item
                                } label: {
                                    Label("查看 / 识别文字", systemImage: "text.viewfinder")
                                }
                            }
                            Button {
                                vm.togglePin(item)
                            } label: {
                                Label(item.isPinned ? "取消收藏" : "收藏",
                                      systemImage: item.isPinned ? "star.slash" : "star")
                            }
                            Divider()
                            Button(role: .destructive) {
                                vm.delete(item)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                vm.delete(item)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                vm.togglePin(item)
                            } label: {
                                Label(item.isPinned ? "取消" : "收藏",
                                      systemImage: item.isPinned ? "star.slash.fill" : "star.fill")
                            }
                            .tint(.yellow)
                        }
                }
            }
            .listStyle(.plain)
            .searchable(text: $vm.searchText, prompt: "搜索剪贴板历史")
            .navigationTitle("ClipKeep")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .navigationDestination(isPresented: $showSettings) {
                SettingsView()
            }
            .overlay {
                if vm.displayedItems.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: vm.searchText.isEmpty ? "clipboard" : "magnifyingglass")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text(vm.searchText.isEmpty ? "暂无历史" : "无匹配结果")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text(vm.searchText.isEmpty ? "复制任意文本后回到这里" : "换个关键词试试")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .toast(isShowing: $showCopiedToast, message: toastMessage)
        .sheet(item: $detailItem) { item in
            ClipDetailView(item: item)
        }
        .onChange(of: scenePhase) { _, new in
            if new == .active { vm.onForeground() }
        }
    }

    private func copy(_ item: ClipItem) {
        toastMessage = vm.copy(item) ? "已复制" : "复制失败"
        showToast()
    }

    private func showToast() {
        toastTimer?.invalidate()
        showCopiedToast = true
        toastTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
            Task { @MainActor in showCopiedToast = false }
        }
    }
}
