#if SUMI
import SwiftUI

struct HonbakoMCPAISetupView: View {
    let client: HonbakoMCPClientGuide
    var endpoint: URL = HonbakoRemoteMCP.endpoint
    private var url: URL {
        (HonbakoRemoteMCP.preferredAIConnectionEndpoint(for: endpoint) ?? endpoint).appendingPathComponent("mcp")
    }

    var body: some View {
        List {
            Group {
                Section {
                    Text("Enable your MCP server in Honbako Settings first. Then connect Honbako to your AI, then approve the connection on this iPhone. No assistant key or pairing code is needed.")
                    LabeledContent("Name", value: "Honbako")
                    LabeledContent("MCP Server URL") { Text(url.absoluteString).textSelection(.enabled) }
                    ShareLink(item: url) { Label("Share Server Address", systemImage: "square.and.arrow.up") }
                } header: { Text("Connection Details") } footer: {
                    Text("Existing AI connections keep working. Add and authorize a new connection to use this address; keep your existing connection unchanged.")
                }
                Section("Connect") {
                    switch client {
                    case .grok:
                        Text("In Grok’s connectors, add a custom MCP connector named Honbako with the server URL above. Choose OAuth and connect. For Grok Bot, ask it to add the remote MCP connection and complete the authorization link it returns.")
                        Link("Open Grok Connectors", destination: URL(string: "https://grok.com/connectors")!)
                    case .chatgpt:
                        Text("In ChatGPT’s custom MCP setup, name the connection Honbako, use the server URL above, and choose OAuth. Connect and follow the authorization link.")
                        Link("Open ChatGPT", destination: URL(string: "https://chatgpt.com/")!)
                    case .claude:
                        Text("In Claude’s connector settings, add a custom connector named Honbako with the server URL above. Connect using OAuth and follow the authorization link.")
                        Link("Open Claude Connectors", destination: URL(string: "https://claude.ai/settings/connectors")!)
                    }
                    Text("Choose Open Honbako on the authorization page. Check the AI name and callback address, then allow access. If setup starts on another device, send its Open Honbako link to your iPhone while keeping that browser tab open.")
                    Text("Enable Honbako in your AI conversation. Connector availability depends on your AI provider and plan.")
                        .foregroundStyle(.secondary)
                }
                Section("Try It") {
                    Text("Use Honbako to tell me what I’m reading. Explain this page without spoilers beyond my current page.")
                        .textSelection(.enabled)
                    Text("Your AI uses only the page Honbako shared. Open the app to share a newer page or approve library changes.")
                        .foregroundStyle(.secondary)
                }
            }
            .honbakoPaperRows()
        }
        .honbakoPaperListBackground()
        .navigationTitle(client.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
