#if SUMI
import SwiftUI

struct HonbakoMCPAuthorizationView: View {
    let requestID: String
    @Environment(\.dismiss) private var dismiss
    @State private var authorization: HonbakoRemoteMCP.Authorization?
    @State private var error: HonbakoMCPAuthorizationError?
    @State private var retryGeneration = 0
    @State private var responseTask: Task<Void, Never>?
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            List {
                Group {
                    if let authorization {
                        Section {
                            Text("Allow \(authorization.clientName) to connect?").font(.title2.bold())
                            LabeledContent("AI callback", value: authorization.callbackHost)
                        }
                        Section {
                            Label("Read your library, reading history and position", systemImage: "books.vertical")
                            Label("Explain and annotate your shared manga page", systemImage: "pencil.tip")
                            Label("Request books and source changes for your approval", systemImage: "checkmark.shield")
                        } footer: { Text("This connection covers your other devices that use the same Pro purchase. Private reading and other apps are never shared. Only approve an AI connection you just started. Disconnect All Devices in MCP Server removes its access.") }
                        Section {
                            Button("Allow Connection") { respond(true) }.disabled(isWorking)
                            Button("Don’t Allow", role: .cancel) { respond(false) }.disabled(isWorking)
                        }
                    } else if error == nil { ProgressView("Checking connection request…") }
                    if let error {
                        Section {
                            Text(error.localizedDescription).foregroundStyle(.secondary)
                            if authorization == nil, error.canRetry {
                                Button("Try Again") { retryGeneration += 1 }
                                    .accessibilityIdentifier("Honbako.MCP.Authorization.Retry")
                            }
                        }
                    }
                }
                .honbakoPaperRows()
            }
            .honbakoPaperListBackground()
            .navigationTitle("Connect Your AI")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .task(id: retryGeneration) { await loadAuthorization() }
            .onDisappear { responseTask?.cancel() }
        }
    }

    private func loadAuthorization() async {
        error = nil
        do {
            let data = try await HonbakoAutomationService.shared.aiAuthorization(requestID: requestID)
            let value = try JSONDecoder().decode(HonbakoRemoteMCP.Authorization.self, from: data)
            try Task.checkCancellation()
            guard value.id == requestID else { throw HonbakoMCPAuthorizationError.invalidResponse }
            authorization = value
        } catch {
            showFailure(error)
        }
    }

    private func showFailure(_ failure: Error) {
        guard !Task.isCancelled else { return }
        if failure is DecodingError {
            error = .invalidResponse
        } else {
            error = failure as? HonbakoMCPAuthorizationError ?? .unavailable
        }
    }

    private func respond(_ approved: Bool) {
        isWorking = true; error = nil
        responseTask = Task { @MainActor in
            defer { isWorking = false }
            do {
                _ = try await HonbakoAutomationService.shared.aiAuthorization(requestID: requestID, approved: approved)
                try Task.checkCancellation()
                dismiss()
            } catch { showFailure(error) }
        }
    }
}
#endif
