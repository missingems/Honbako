#if SUMI
import SwiftUI

struct HonbakoMCPClientGuideView: View {
    let client: HonbakoMCPClientGuide
    let companionEndpoint: String

    private var mcpURL: URL? { HonbakoMCPClientGuide.remoteMCPURL(companionEndpoint: companionEndpoint) }
    private var serverAddress: String { mcpURL?.absoluteString ?? "https://your-honbako-server.example/mcp" }

    var body: some View {
        List {
            Section {
                if client == .chatgpt {
                    Label("OAuth support needed", systemImage: "key")
                    Text("Honbako’s current server uses an assistant key. ChatGPT web requires OAuth and cannot accept this key as a custom request header. Add OAuth to the server before following the steps below.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Connect this AI app to the same server that your iPhone uses. Keep Honbako open when asking about a new manga page.")
                }
            }
            Section {
                LabeledContent("Name", value: "Honbako")
                if let mcpURL {
                    LabeledContent("MCP Server URL") { Text(mcpURL.absoluteString).textSelection(.enabled) }
                } else {
                    Text("No remote MCP URL is available from this phone’s connection yet.")
                    LabeledContent("Example URL") { Text(serverAddress).textSelection(.enabled) }
                }
                if client != .chatgpt {
                    Text("Use the private assistant key supplied when your server is set up. The phone’s pairing code is not the assistant key. Enter keys only in the AI app’s secure credential field.")
                        .foregroundStyle(.secondary)
                }
            } header: { Text("Connection Details") }
            footer: {
                Text("The URL must end in /mcp and be reachable online. A localhost or Wi-Fi address on your Mac will not work for a cloud AI.")
            }

            switch client {
            case .grok:
                Section("Grok Bot") {
                    step(1, "In a Grok Bot chat, ask it to add Honbako as a remote MCP server using the URL above and Streamable HTTP.")
                    step(2, "Review its connection card. When asked, supply the assistant key through the secure secret field, not an ordinary chat message.")
                    step(3, "Ask Grok to call honbako_get_status, choose this iPhone, then fetch its reading context or shared manga page.")
                    ShareLink(item: "Add Honbako as a remote Streamable HTTP MCP server at \(serverAddress). Ask me for its assistant key using a secure secret field. Then call honbako_get_status and help me select my iPhone.") {
                        Label("Share Setup Request", systemImage: "square.and.arrow.up")
                    }
                    Link("Official Grok Bot Instructions", destination: URL(string: "https://docs.x.ai/grok-bot/computer-and-apps")!)
                }
                Section("Grok Website") {
                    step(1, "Open grok.com/connectors, choose New Connector, then Custom.")
                    step(2, "Enter the MCP Server URL and complete the authentication Grok offers. If it only offers OAuth, this key-based server needs OAuth support first; use Grok Bot meanwhile.")
                    step(3, "Enable Honbako in your conversation and ask what you are reading.")
                    Link("Open Grok Connectors", destination: URL(string: "https://grok.com/connectors")!)
                    Link("Official Grok Instructions", destination: URL(string: "https://docs.x.ai/grok/connectors")!)
                }
            case .chatgpt:
                Section("After OAuth Is Available") {
                    step(1, "On ChatGPT web, open Plugins. Choose +, then Add custom MCP server.")
                    step(2, "Set the name to Honbako and enter the MCP Server URL. Choose OAuth and complete your server’s sign-in. No authentication will not connect Honbako’s protected server.")
                    step(3, "Create and install the plugin. In a chat, type @ and choose Honbako. Ask it to check your reading context or shared page.")
                    Link("Open ChatGPT Plugins", destination: URL(string: "https://chatgpt.com/plugins")!)
                    Link("Official ChatGPT Instructions", destination: URL(string: "https://developers.openai.com/api/docs/guides/custom-mcp-server")!)
                }
            case .claude:
                Section("Claude Web or Desktop") {
                    step(1, "Open Customize → Connectors → + Add → Add custom connector. Enter Honbako and the MCP Server URL.")
                    step(2, "For this server’s key-based authentication, skip OAuth sign-in and add a Request header: Authorization, with the value Bearer followed by a space and your private assistant key.")
                    step(3, "Finish adding it. In your chat, open + → Connectors and enable Honbako. Ask Claude to check your reading context or shared page.")
                    Text("The Authorization header still protects the connection when OAuth sign-in is skipped. Never remove the header or paste the phone’s pairing code into it.")
                        .foregroundStyle(.secondary)
                    Link("Open Claude Connectors", destination: URL(string: "https://claude.ai/settings/connectors")!)
                    Link("Official Claude Instructions", destination: URL(string: "https://support.claude.com/en/articles/11175166-get-started-with-custom-connectors-using-remote-mcp")!)
                }
            }
            Section("Try It") {
                Text("Use Honbako to tell me what I’m reading and explain this page without spoiling anything after my current page.")
                    .textSelection(.enabled)
                Text("If no page is available, open a book in Honbako with Reading Access on. When the app is in the background, your assistant can use only the last shared page.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(client.title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("Honbako.MCP.GuideDetail.\(client.rawValue)")
    }

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        Label { Text(text) } icon: { Image(systemName: "\(number).circle") }
    }
}
#endif
