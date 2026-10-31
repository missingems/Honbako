#if SUMI
import SwiftUI

struct HonbakoWelcomeStepsList: View {
    @Binding var selection: HonbakoWelcomePage?
    let onFinish: () -> Void

    var body: some View {
        List {
            Group {
                Section("Get Started") {
                    ForEach(HonbakoWelcomePage.allCases) { page in
                        Button {
                            selection = page
                        } label: {
                            HStack {
                                Label(page.navigationTitle, systemImage: page.symbol)
                                Spacer()
                                if selection == page {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                        .accessibilityIdentifier("Honbako.Welcome.Step.\(page.rawValue)")
                        .accessibilityAddTraits(selection == page ? .isSelected : [])
                    }
                }
                Section {
                    Button("Start Reading", systemImage: "book", action: onFinish)
                        .accessibilityIdentifier("Honbako.Welcome.StartReading")
                }
            }
            .honbakoPaperRows()
        }
        .honbakoPaperListBackground()
        .listStyle(.sidebar)
        .navigationTitle("Welcome")
    }
}
#endif
