import SwiftUI

struct RootView: View {
    @StateObject private var vm = ClipListViewModel()

    var body: some View {
        ClipListView(vm: vm)
            .sheet(isPresented: $vm.showOnboarding) {
                OnboardingView { vm.dismissOnboarding() }
                    .interactiveDismissDisabled()
            }
    }
}
