import SwiftUI

@main
struct ItsJustAGameApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            HomeView(model: model)
                .onOpenURL { url in
                    model.handle(url: url)
                }
                .preferredColorScheme(.dark)
        }
    }
}
