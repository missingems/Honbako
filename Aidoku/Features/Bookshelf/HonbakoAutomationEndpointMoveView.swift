#if SUMI
import SwiftUI

struct HonbakoAutomationEndpointMoveView: View {
    @ObservedObject var service: HonbakoAutomationService
    @Environment(\.dismiss) private var dismiss
    @State private var endpoint = ""
    @State private var attemptedMove = false
    @FocusState private var focused: Bool

    private var validAddress: Bool {
        HonbakoAutomationPolicy.endpoint(endpoint)?.scheme == "https"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Current Companion", value: service.endpoint)
                    TextField("https://your-companion.example", text: $endpoint)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .disabled(service.isMovingConnection)
                        .accessibilityLabel("New HTTPS Companion Address")
                        .accessibilityIdentifier("Honbako.Automation.Move.Endpoint")
                        .onSubmit(move)
                } footer: {
                    Text("Use the HTTPS address of the companion that already has your paired device and pending requests. Your hosted companion stores shared library metadata and any reading position you enable. Existing approvals and reading settings stay intact.")
                }
                if attemptedMove, let error = service.errorMessage {
                    Section {
                        Text(error).foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .accessibilityIdentifier("Honbako.Automation.Move.Error")
                    }
                }
            }
            .accessibilityIdentifier("Honbako.Automation.Move.Form")
            .navigationTitle("Move Connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(service.isMovingConnection)
                        .accessibilityIdentifier("Honbako.Automation.Move.Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: move) {
                        if service.isMovingConnection { ProgressView() }
                        else { Text("Move") }
                    }
                    .disabled(!validAddress || service.isMovingConnection)
                    .accessibilityIdentifier("Honbako.Automation.Move.Submit")
                }
            }
            .task { focused = true }
        }
        .interactiveDismissDisabled(service.isMovingConnection)
    }

    private func move() {
        guard validAddress, !service.isMovingConnection else { return }
        attemptedMove = true
        focused = false
        Task {
            if await service.moveConnection(to: endpoint) { dismiss() }
        }
    }
}
#endif
