#if SUMI
import AidokuRunner
import SwiftUI

struct HonbakoSourceReconnectView: View {
    let sourceID: String
    @Environment(\.dismiss) private var dismiss
    @State private var source: AidokuRunner.Source?
    @State private var loading = true

    var body: some View {
        Group {
            if let source { SourceSettingsController(source: source) }
            else {
                NavigationStack {
                    Group {
                        if loading { ProgressView("Opening connection…") }
                        else {
                            ContentUnavailableView("Connection Unavailable", systemImage: "externaldrive.badge.exclamationmark",
                                description: Text("Reconnect this personal server from Settings, then try again."))
                        }
                    }
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
                }
            }
        }
        .task {
            source = await SourceManager.shared.sourceSetupSettingsSource(id: sourceID)
            loading = false
        }
    }

    /// The existing source settings use NavigationCoordinator for login subpages.
    private struct SourceSettingsController: UIViewControllerRepresentable {
        let source: AidokuRunner.Source
        func makeUIViewController(context: Context) -> UINavigationController {
            let coordinator = NavigationCoordinator(rootViewController: nil)
            let controller = UIHostingController(rootView: SourceSettingsView(source: source).environmentObject(coordinator))
            coordinator.rootViewController = controller
            return UINavigationController(rootViewController: controller)
        }
        func updateUIViewController(_ controller: UINavigationController, context: Context) {}
    }
}
#endif
