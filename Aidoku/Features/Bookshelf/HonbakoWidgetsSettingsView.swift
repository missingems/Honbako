#if SUMI
import SwiftUI

struct HonbakoWidgetsSettingsView: View {
    @State private var snapshot = HonbakoWidgetSnapshot.read()
    @State private var showingPro = false

    var body: some View {
        List {
            Group {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Continue Reading", systemImage: "book.closed")
                            .font(.headline)
                        HonbakoResumeWidgetView(snapshot: snapshot, expanded: true)
                            .frame(height: 132)
                        Text("Free · Small and medium widgets")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
                Section("More Widgets") {
                    VStack(alignment: .leading, spacing: 12) {
                        HonbakoReadingTimeWidgetView(snapshot: snapshot, date: .now, expanded: true)
                            .frame(height: 132)
                        Text("Reading Time · Small and medium widgets")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                    VStack(alignment: .leading, spacing: 12) {
                        HonbakoUpdatesWidgetView(snapshot: snapshot, date: .now)
                            .frame(height: 150)
                        Text("New Chapters · Medium and large widgets")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                    if !snapshot.hasPro(at: .now) {
                        Button("Get All Widgets") { showingPro = true }
                    }
                }
                Section("Add a Widget") {
                    Text("Touch and hold your Home Screen, tap Edit, then Add Widget. Search for Honbako and choose a widget.")
                    Text("Reading time uses saved reading sessions. Chapter updates refresh when Honbako checks your library; they may not appear immediately.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .honbakoPaperRows()
        }
        .honbakoPaperListBackground()
        .navigationTitle("Widgets")
        .sheet(isPresented: $showingPro) { HonbakoProView(feature: .widgets) }
        .task {
            await HonbakoWidgetPublisher.shared.publish()
            snapshot = .read()
        }
    }
}
#endif
