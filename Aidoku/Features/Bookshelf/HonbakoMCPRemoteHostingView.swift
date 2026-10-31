#if SUMI
import SwiftUI

struct HonbakoMCPRemoteHostingView: View {
    var body: some View {
        List {
            Group {
                Section {
                    Label("Your Mac can stay off", systemImage: "cloud")
                    Text("A hosted Honbako server gives your iPhone and AI app a stable HTTPS address. It stores your shared library and reading snapshot, plus the last manga page you chose to share through Reading Access.")
                }
                Section("Set Up Free Hosting") {
                    Label("Sign in to Cloudflare and confirm the account uses Workers Free before publishing.", systemImage: "1.circle")
                    Label("Publish the prepared Honbako server with separate phone-pairing and assistant credentials. Copy its HTTPS address and private assistant connection details.", systemImage: "2.circle")
                    Label("Migrate your existing pairing and queued work first. Then use Move to Remote Server in Honbako; this keeps your phone identity and reading progress.", systemImage: "3.circle")
                    Label("Update Grok or Claude with the new /mcp URL. ChatGPT additionally needs OAuth support on the server.", systemImage: "4.circle")
                    Link("Open Cloudflare Dashboard", destination: URL(string: "https://dash.cloudflare.com/")!)
                }
                Section("While You Read") {
                    Text("Keep Honbako open to upload new reading positions and pages or process library requests. When it is closed or offline, your assistant sees the last shared information. Your Mac is no longer part of that connection.")
                }
                Section("Hosting Limits") {
                    Text("Use only Workers Free. Free-plan limits can temporarily stop requests; do not enable a paid upgrade to keep the server running. Hosting does not include an AI subscription.")
                }
            }
            .honbakoPaperRows()
        }
        .honbakoPaperListBackground()
        .navigationTitle("Remote MCP Server")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("Honbako.MCP.RemoteHostingDetail")
    }
}
#endif
