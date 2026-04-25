import SwiftUI

struct ToastModifier: ViewModifier {
    @Binding var isShowing: Bool
    let message: String

    func body(content: Content) -> some View {
        ZStack(alignment: .bottom) {
            content
            if isShowing {
                Text(message)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 32)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: isShowing)
    }
}

extension View {
    func toast(isShowing: Binding<Bool>, message: String) -> some View {
        modifier(ToastModifier(isShowing: isShowing, message: message))
    }
}
