#if SUMI
import SwiftUI

struct SumiPersonalLibrariesView: View {
    var body: some View {
        List {
            Group {
                Section {
                    NavigationLink("Komga") { KomgaSetupView() }
                    NavigationLink("Kavita") { KavitaSetupView() }
                    NavigationLink("Suwayomi") { SuwayomiSetupView() }
                } footer: { Text("Honbako.CollectionGuide.Server.Body") }
            }
            .honbakoPaperRows()
        }
        .honbakoPaperListBackground()
        .navigationTitle("Personal Server")
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
