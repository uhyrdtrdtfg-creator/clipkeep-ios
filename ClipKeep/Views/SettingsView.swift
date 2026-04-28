import SwiftUI
import ClipKeepCore

struct SettingsView: View {
    @State private var maxCount: Int = ClipStore.shared.getMaxCount()
    @State private var maxRetentionDays: Int = ClipStore.shared.getMaxRetentionDays()
    @State private var showClearAllAlert = false
    @State private var showClearUnpinnedAlert = false

    private let maxOptions = [100, 200, 500, 1000]
    private let retentionOptions: [(label: String, days: Int)] = [
        ("永久保存", 0),
        ("7 天", 7),
        ("30 天", 30),
        ("3 个月", 90),
        ("6 个月", 180),
        ("1 年", 365),
    ]

    var body: some View {
        Form {
            Section("历史容量") {
                Picker("最大条数", selection: $maxCount) {
                    ForEach(maxOptions, id: \.self) { n in
                        Text("\(n) 条").tag(n)
                    }
                }
                .onChange(of: maxCount) { value in
                    ClipStore.shared.setMaxCount(value)
                }

                Picker("最长保存时间", selection: $maxRetentionDays) {
                    ForEach(retentionOptions, id: \.days) { opt in
                        Text(opt.label).tag(opt.days)
                    }
                }
                .onChange(of: maxRetentionDays) { value in
                    ClipStore.shared.setMaxRetentionDays(value)
                }
            }

            Section("清理") {
                Button("清空所有历史", role: .destructive) {
                    showClearAllAlert = true
                }
                Button("清空非收藏历史", role: .destructive) {
                    showClearUnpinnedAlert = true
                }
            }

            Section("关于") {
                LabeledContent("版本",
                    value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-")
                LabeledContent("Build",
                    value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-")
            }

            Section("键盘设置") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("如何启用 ClipKeep 键盘")
                        .font(.headline)
                    Text("1. 打开「设置」→「通用」→「键盘」→「键盘」\n2. 点击「添加新键盘」→ 选择 ClipKeep\n3. 再次点击 ClipKeep → 打开「允许完全访问」")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .alert("清空所有历史？", isPresented: $showClearAllAlert) {
            Button("清空", role: .destructive) { ClipStore.shared.clearAll() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作不可撤销，包括收藏内容也会被删除。")
        }
        .alert("清空非收藏历史？", isPresented: $showClearUnpinnedAlert) {
            Button("清空", role: .destructive) { ClipStore.shared.clearUnpinned() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("收藏的内容将保留。")
        }
    }
}
