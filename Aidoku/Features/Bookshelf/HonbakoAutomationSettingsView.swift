#if SUMI
import SwiftUI

struct HonbakoAutomationSettingsView: View {
    @ObservedObject private var service = HonbakoAutomationService.shared
    @ObservedObject private var pro = HonbakoProStore.shared
    @State private var showingPro = false
    @State private var isPreparing = false
    @State private var remote = true
    @State private var localAddress = ""
    @State private var pairingCode = ""
    @State private var askingConsent = false
    @State private var consented: (() -> Void)?
    @State private var confirmingDisconnectAll = false

    var body: some View {
        Form {
            Group {
                Section {
                    Picker("Connection", selection: $remote) {
                        Text("Remote").tag(true)
                        Text("Local").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .disabled(service.isEnabled || isChangingConnection)
                    .accessibilityIdentifier("Honbako.MCP.Mode")
                    if remote {
                        Toggle(isOn: Binding(get: { service.isEnabled && service.usesManagedRemote },
                            set: { enabled in Task { await setServerEnabled(enabled) } })) {
                            HStack {
                                Text("Connect Remotely")
                                if isChangingConnection { ProgressView().accessibilityLabel("Connecting") }
                            }
                        }
                        .disabled(isChangingConnection)
                        .accessibilityIdentifier("Honbako.MCP.Enable")
                        if sharesWithOtherDevices {
                            Label("Connected with your other devices", systemImage: "checkmark.circle")
                                .accessibilityIdentifier("Honbako.MCP.Joined")
                        }
                        if !service.isEnabled, service.remoteSetupAvailable == false {
                            Text(service.remoteSetupMessage ?? "Couldn’t reach remote hosting.").foregroundStyle(.secondary)
                                .accessibilityIdentifier("Honbako.MCP.RemoteStatus")
                            Button("Try Again", systemImage: "arrow.clockwise") {
                                Task { await service.checkRemoteAvailability() }
                            }
                            .disabled(isChangingConnection)
                            .accessibilityIdentifier("Honbako.MCP.Retry")
                        }
                    } else {
                        localConnection
                    }
                    if let error = service.errorMessage { Text(error).foregroundStyle(.secondary) }
                    if let limit = service.limitMessage {
                        Label(limit, systemImage: "hourglass").foregroundStyle(.secondary)
                            .accessibilityIdentifier("Honbako.MCP.Limit")
                    }
                } footer: {
                    Text(remote ? "Remote access is included with Pro. Your Mac can stay off."
                        : "Use your Mac’s IP address on the same network. Its one-time pairing code protects access. Disconnect before changing connection type.")
                }

                Section {
                    LabeledContent("MCP Server URL") {
                        Text(serverAddress).textSelection(.enabled)
                            .accessibilityIdentifier("Honbako.MCP.URL")
                    }
                    ForEach(HonbakoMCPClientGuide.allCases) { client in
                        NavigationLink {
                            HonbakoMCPClientGuideView(client: client, companionEndpoint: selectedEndpoint)
                        } label: { Text(client.title) }
                        .accessibilityIdentifier("Honbako.MCP.Guide.\(client.rawValue)")
                    }
                } header: { Text("Connect to an AI Provider") } footer: {
                    if remote {
                        Text("Existing AI connections keep working. Add and authorize a new connection to use this address; keep your existing connection unchanged.")
                    }
                }

                if !service.pendingApprovals.isEmpty || !service.handledNotices.isEmpty {
                    Section("Waiting for Your Approval") {
                        ForEach(service.pendingApprovals) { approval in
                            NavigationLink { HonbakoAutomationApprovalView(jobID: approval.id) } label: {
                                Label(approval.title, systemImage: approval.isSourceChange ? "externaldrive" : approval.isRemoval ? "trash" : "books.vertical")
                            }
                        }
                        ForEach(service.handledNotices) { notice in
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(notice.title)
                                    Text("Handled on \(notice.deviceName)").font(.footnote).foregroundStyle(.secondary)
                                }
                            } icon: { Image(systemName: "checkmark.circle") }
                            .accessibilityIdentifier("Honbako.MCP.Handled.\(notice.id)")
                        }
                    }
                }

                if service.isEnabled && service.usesManagedRemote && !service.devices.isEmpty {
                    devicesSection
                }

                Section {
                    permission("Read Library and Sources", key: "LibraryAccess", value: service.libraryAccessAllowed)
                    Toggle("Read Reading History and Progress", isOn: Binding(get: { service.sharesReadingPosition }, set: { service.setSharingReading($0) }))
                        .accessibilityIdentifier("Honbako.MCP.Permission.History")
                    permission("View Manga Pages", key: "PageAccess", value: service.pageAccessAllowed)
                    permission("Change Library", key: "LibraryChanges", value: service.libraryChangesAllowed)
                    permission("Manage Sources", key: "SourceChanges", value: service.sourceChangesAllowed)
                    permission("Annotate Manga Pages", key: "Annotations", value: service.annotationsAllowed)
                } header: { Text("MCP Permissions") } footer: {
                    Text(service.isEnabled && service.usesManagedRemote
                        ? "Choose what connected AIs can access. These switches are the same on all your connected devices. Adding or removing books and changing sources also need your approval on one of them. Private reading is excluded. Open Honbako to sync changes and process requests."
                        : "Choose what connected AIs can access. Adding or removing books and changing sources also need your approval. Private reading is excluded. Open Honbako to sync changes and process requests.")
                }
            }
            .honbakoPaperRows()
        }
        .honbakoPaperListBackground()
        .navigationTitle("MCP Server")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPro) { HonbakoProView(feature: .remoteMCP) }
        .honbakoAIConsent(isPresented: $askingConsent, remote: remote) { consented?() }
        .confirmationDialog("Disconnect All Devices?", isPresented: $confirmingDisconnectAll, titleVisibility: .visible) {
            Button("Disconnect All Devices", role: .destructive) { Task { await service.disconnectAllDevices() } }
        } message: {
            Text("Every device on your Pro purchase stops sharing with your AI, and every AI connection is removed. You can connect again later.")
        }
        .task {
            if service.isEnabled { remote = service.usesManagedRemote }
            if !service.usesManagedRemote { localAddress = service.endpoint }
            await service.checkRemoteAvailability()
            await pro.refreshEntitlement()
        }
    }

    private var sharesWithOtherDevices: Bool {
        service.isEnabled && service.usesManagedRemote && (service.joinedOtherDevices || service.devices.count > 1)
    }

    private var devicesSection: some View {
        Section {
            ForEach(service.devices) { device in
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.displayName)
                    if device.thisDevice {
                        Text("This Device").font(.footnote).foregroundStyle(.secondary)
                    } else if let date = device.lastActiveDate {
                        Text("Last active \(date.formatted(.relative(presentation: .named)))").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("Honbako.MCP.Device.\(device.deviceId)")
                .swipeActions {
                    Button(device.thisDevice ? "Turn Off" : "Remove", role: .destructive) {
                        Task { await service.removeDevice(device.deviceId) }
                    }
                }
            }
            Button("Disconnect All Devices", role: .destructive) { confirmingDisconnectAll = true }
                .disabled(isChangingConnection || service.isRemovingDevice)
                .accessibilityIdentifier("Honbako.MCP.DisconnectAll")
        } header: { Text("Devices") } footer: {
            Text("One AI connection covers up to five of your devices with the same Pro purchase. Swipe to remove a device. Disconnect All Devices also removes every AI connection.")
        }
    }

    @ViewBuilder private var localConnection: some View {
        if service.isEnabled && !service.usesManagedRemote {
            Label("Connected", systemImage: "checkmark.circle")
                .accessibilityIdentifier("Honbako.MCP.Local.Connected")
            Button("Disconnect", role: .destructive) { Task { await service.disconnect() } }
                .disabled(isChangingConnection)
                .accessibilityIdentifier("Honbako.Automation.Disconnect")
        } else {
            TextField("Mac IP Address", text: $localAddress)
                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityIdentifier("Honbako.Automation.Endpoint")
            SecureField("One-Time Pairing Code", text: $pairingCode)
                .textContentType(.oneTimeCode).textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityIdentifier("Honbako.Automation.Code")
            Button {
                askConsent {
                    Task {
                        await service.connect(endpoint: selectedEndpoint, code: pairingCode)
                        if service.isEnabled { pairingCode = "" }
                    }
                }
            } label: {
                if service.isConnecting { ProgressView() } else { Text("Connect") }
            }
            .disabled(localAddress.isEmpty || pairingCode.isEmpty || isChangingConnection)
            .accessibilityIdentifier("Honbako.Automation.Connect")
        }
    }

    private func permission(_ title: String, key: String, value: Bool) -> some View {
        Toggle(title, isOn: Binding(get: { value }, set: { service.setPermission(key, enabled: $0) }))
            .accessibilityIdentifier("Honbako.MCP.Permission.\(key)")
    }
    private var isChangingConnection: Bool { isPreparing || service.isConnecting || service.isDisconnecting || service.isMovingConnection }
    private var selectedEndpoint: String {
        if service.isEnabled { return service.endpoint }
        if remote { return HonbakoRemoteMCP.endpoint.absoluteString }
        let input = localAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if input.contains("://") { return input }
        return input.contains(":") ? "http://\(input)" : "http://\(input):43187"
    }
    private var serverAddress: String {
        if !remote, localAddress.isEmpty, !service.isEnabled { return "http://<Mac IP>:43187/mcp" }
        guard let endpoint = URL(string: selectedEndpoint) else { return selectedEndpoint }
        let address = HonbakoRemoteMCP.preferredAIConnectionEndpoint(for: endpoint) ?? endpoint
        return address.appendingPathComponent("mcp").absoluteString
    }
    private func setServerEnabled(_ enabled: Bool) async {
        guard !isChangingConnection else { return }
        guard enabled else { await service.disconnect(); return }
        isPreparing = true
        defer { isPreparing = false }
        guard await service.checkRemoteAvailability() else { return }
        await pro.refreshEntitlement()
        if pro.hasVerifiedPro { askConsent { Task { await service.enableRemoteServer() } } }
        else { showingPro = true }
    }
    private func askConsent(then action: @escaping () -> Void) {
        consented = action
        askingConsent = true
    }
}

extension View {
    /// Asked before every pairing: what a connected AI can read, and that the
    /// AI provider's own terms and privacy policy apply to it from then on.
    func honbakoAIConsent(isPresented: Binding<Bool>, remote: Bool = false, onContinue: @escaping () -> Void) -> some View {
        alert("Share with Your AI?", isPresented: isPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Continue", action: onContinue)
        } message: {
            Text(remote
                ? "Connected AIs, such as ChatGPT, Claude or Grok, can read your library, reading history and the manga page you’re viewing, and can ask to add or remove books, or change sources, for you to approve. Remote MCP is shared by your other devices that use the same Pro purchase, so AIs you connect can also read what those devices share. What they receive is handled under that AI provider’s own privacy policy. You can turn off each kind of access in MCP Permissions, or disconnect at any time."
                : "Connected AIs, such as ChatGPT, Claude or Grok, can read your library, reading history and the manga page you’re viewing, and can ask to add or remove books, or change sources, for you to approve. What they receive is handled under that AI provider’s own privacy policy. You can turn off each kind of access in MCP Permissions, or disconnect at any time.")
        }
    }
}
#endif
