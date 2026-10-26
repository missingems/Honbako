#if SUMI
import SwiftUI

struct SumiPersonalLibrariesView: View {
    var body: some View {
        List {
            Section {
                NavigationLink("Komga") { KomgaSetupView() }
                NavigationLink("Kavita") { KavitaSetupView() }
                NavigationLink("Suwayomi") { SuwayomiSetupView() }
            } footer: { Text("Connect to a server you manage to search your own library.") }
        }
        .navigationTitle("Personal Server")
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
