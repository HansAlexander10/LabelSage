import SwiftUI

@main
struct LabelSageApp: App {
    var body: some Scene {
        WindowGroup {
            // `-gallery` launch argument: the design-system gallery instead of the app.
            if ProcessInfo.processInfo.arguments.contains("-gallery") {
                DesignGallery()
            } else {
                RootView()
            }
        }
    }
}

/// Placeholder root until the onboarding and chat milestones land.
struct RootView: View {
    var body: some View {
        Text(Brand.app)
    }
}
