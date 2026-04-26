import SwiftUI

struct RootView: View {
    @StateObject private var vm = ClipListViewModel()

    var body: some View {
        TabView {
            ClipListView(vm: vm)
                .tabItem { Label("历史", systemImage: "clock") }

            FavoritesView(vm: vm)
                .tabItem { Label("收藏", systemImage: "star.fill") }
        }
        .sheet(isPresented: $vm.showOnboarding) {
            OnboardingView { vm.dismissOnboarding() }
                .interactiveDismissDisabled()
        }
    }
}
