#if SUMI
import SwiftUI

struct HonbakoAutomationSettingsView: View {
    @ObservedObject private var service = HonbakoAutomationService.shared
    @State private var endpoint = ""
    @State private var code = ""
    @State private var showingEndpointMove = false

    var body: some View {
        Form {
            Section {
                Label(service.status, systemImage: service.isEnabled ? "checkmark.circle" : "desktopcomputer")
                    .accessibilityIdentifier("Honbako.Automation.Status")
                if let lastSync = service.lastSync, service.isEnabled {
                    LabeledContent("Last Update") { Text(lastSync, style: .relative) }
                }
                if let error = service.errorMessage {
                    Text(error).foregroundStyle(.secondary)
                }
            } header: { Text("Connection Status") }
            footer: {
                Text("First connect Honbako to your server below. Then add that server in Grok, ChatGPT or Claude. The server runs on your Mac or online; this screen connects your phone to it.")
            }

            if !service.isEnabled {
                Section {
                    TextField("https://your-companion.example", text: $endpoint)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Companion Address")
                        .accessibilityIdentifier("Honbako.Automation.Endpoint")
                    SecureField("One-Time Pairing Code", text: $code)
                        .textContentType(.oneTimeCode)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("Honbako.Automation.Code")
                    Button {
                        Task {
                            await service.connect(endpoint: endpoint, code: code)
                            if service.isEnabled { code = "" }
                        }
                    } label: {
                        if service.isConnecting { ProgressView().frame(maxWidth: .infinity) }
                        else { Text("Connect Honbako") }
                    }
                    .disabled(service.isConnecting || endpoint.isEmpty || code.isEmpty)
                    .accessibilityIdentifier("Honbako.Automation.Connect")
                } header: { Text("1. Connect This iPhone") }
                footer: { Text("Enter your companion’s address and pairing code. Mac companions on a trusted local network can also use a local HTTP address.") }
            } else {
                Section {
                    LabeledContent("Companion", value: service.endpoint)
                        .textSelection(.enabled)
                    Button("Move to Remote Server", systemImage: "arrow.right.arrow.left") {
                        showingEndpointMove = true
                    }
                    .disabled(service.isMovingConnection || service.isDisconnecting || service.approvingJobID != nil)
                    .accessibilityIdentifier("Honbako.Automation.Move")
                    Button("Disconnect Honbako", role: .destructive) { Task { await service.disconnect() } }
                    .disabled(service.isDisconnecting || service.isMovingConnection)
                    .accessibilityIdentifier("Honbako.Automation.Disconnect")
                } footer: { Text("The companion works while Honbako is open. Move the existing pairing to a migrated HTTPS companion, or disconnect to remove this device and its requests when the companion is reachable.") }
            }

            Section {
                ForEach(HonbakoMCPClientGuide.allCases) { client in
                    NavigationLink {
                        HonbakoMCPClientGuideView(client: client, companionEndpoint: service.endpoint)
                    } label: { Text(client.title) }
                    .accessibilityIdentifier("Honbako.MCP.Guide.\(client.rawValue)")
                }
            } header: { Text("2. Connect Your AI App") }
            footer: {
                Text("Each guide lists the exact setup fields and whether this server supports that app’s sign-in method. Your AI app needs an internet-reachable HTTPS MCP URL.")
            }

            Section {
                NavigationLink {
                    HonbakoMCPRemoteHostingView()
                } label: {
                    Label("Use a Remote MCP Server", systemImage: "cloud")
                }
                .accessibilityIdentifier("Honbako.MCP.RemoteHosting")
            } footer: { Text("A hosted server keeps working when your Mac is off.") }

            Section {
                Toggle("Reading Access", isOn: Binding(
                    get: { service.sharesReadingPosition },
                    set: { service.setSharingReading($0) }
                ))
                .disabled(service.isMovingConnection)
                .accessibilityIdentifier("Honbako.Automation.ShareReading")
            } footer: {
                Text("On when you connect. Your assistant can read and annotate the current manga page without a separate start button or timer. The last shared page remains available in the background. Private reading, other apps, passwords and cookies are not shared.")
            }

            if !service.pendingApprovals.isEmpty {
                Section("Waiting For Your Approval") {
                    ForEach(service.pendingApprovals) { approval in
                        NavigationLink {
                            HonbakoAutomationApprovalView(jobID: approval.id)
                        } label: {
                            Label("Add \(approval.items.count) Books", systemImage: "books.vertical")
                        }
                        .disabled(service.isMovingConnection)
                        .accessibilityIdentifier("Honbako.Automation.Request.\(approval.id)")
                    }
                }
            }
        }
        .navigationTitle("MCP Server")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingEndpointMove) { HonbakoAutomationEndpointMoveView(service: service) }
        .task { if endpoint.isEmpty { endpoint = service.endpoint } }
        .onDisappear { code = "" }
    }
}
#endif
