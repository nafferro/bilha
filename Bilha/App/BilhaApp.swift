import SwiftUI

@main
struct BilhaApp: App {
    @State private var manager = BottleManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(manager)
                .tint(Color("Accent"))
                .fontDesign(.rounded)
        }
    }
}

struct RootView: View {
    @State private var path: [UUID] = []
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.system.rawValue

    var body: some View {
        NavigationStack(path: $path) {
            BottlesView(path: $path)
                .navigationDestination(for: UUID.self) { BottleView(id: $0) }
        }
        // Rebuild every screen when the language changes, so it applies at once.
        .id(language)
        .environment(\.locale, AppLanguage.locale)
    }
}
