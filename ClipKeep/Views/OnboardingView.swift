import SwiftUI

struct OnboardingView: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            Image(systemName: "clipboard.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            VStack(spacing: 12) {
                Text("欢迎使用 ClipKeep")
                    .font(.largeTitle.bold())
                Text("记录你复制过的每一段文字，随时找回。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 16) {
                StepRow(number: "1", text: "在任意 App 复制文本，回到 ClipKeep 即自动记录。")
                StepRow(number: "2", text: "点击列表条目即可复制回剪贴板。")
                StepRow(number: "3", text: "在设置里启用 ClipKeep 键盘，可在任意输入框快速粘贴历史。")
            }
            .padding(.horizontal)

            Spacer()

            Button {
                onDismiss()
            } label: {
                Text("开始使用")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.tint, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
    }
}

private struct StepRow: View {
    let number: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.headline)
                .frame(width: 28, height: 28)
                .background(.tint.opacity(0.15), in: Circle())
                .foregroundStyle(.tint)
            Text(text)
                .font(.body)
        }
    }
}
