#if SUMI
import SwiftUI

struct SumiPersonalLibrariesView: View {
    var body: some View {
        List {
            Section {
                NavigationLink("Komga") { KomgaSetupView() }
                NavigationLink("Kavita") { KavitaSetupView() }
                NavigationLink("Suwayomi") { SuwayomiSetupView() }
            } footer: { Text("Honbako.CollectionGuide.Server.Body") }
        }
        .navigationTitle("Personal Server")
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
