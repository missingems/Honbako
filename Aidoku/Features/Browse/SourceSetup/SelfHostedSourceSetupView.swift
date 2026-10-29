//
//  SelfHostedSourceSetupView.swift
//  Aidoku
//
//  Created by Skitty on 10/19/25.
//

import SwiftUI

struct ServerCheck: Hashable {
    var canSkipLogin: Bool = false
    var canLoginBasic: Bool = false
    var canLoginApiKey: Bool = false
    var canLoginOIDC: Bool = false
    var oidcLoginURL: URL?

    var hasLoginMethod: Bool {
        canSkipLogin || canLoginBasic || canLoginApiKey || canLoginOIDC
    }

    var mustSkipLogin: Bool {
        canSkipLogin && !canLoginBasic && !canLoginApiKey && !canLoginOIDC
    }
}

struct SelfHostedSourceSetupView: View {
    let icon: Image
    let title: String
    let sourceName: String
    let info: String
    let learnMoreUrl: URL?
    let sourceKeyPrefix: String
    let useEmail: Bool
    let placeholderServer: String?

    let demoServer: String?
    let demoTitle: String?
    let demoInfo: String?

    private let checkHandler: (String) async -> ServerCheck
    private let logInHandler: (String, URL, String, String) async -> Bool
    private let apiKeyLogInHandler: ((String, URL, String) async -> Bool)?
    private let oidcLogInHandler: ((String, URL, [HTTPCookie]) async -> Bool)?
    private let noLogInHandler: ((String, URL) async -> Bool)?

    @State private var name: String = ""
    @State private var server: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var apiKey: String = ""
    @State private var loginMethod: LoginMethod = .apiKey

    enum LoginMethod {
        case apiKey
        case basic
        case oidc
    }

    private enum ViewState: Equatable {
        case initial
        case loading
        case logIn(ServerCheck)
        case loadingLogin(ServerCheck)
    }

    private enum ServerError {
        case connection
        case authorization
    }

    @State private var state: ViewState = .initial
    @State private var error: ServerError?
    @State private var showLoginSheet = false

    private var isLogInState: Bool {
        if case .logIn = state { return true }
        return false
    }
    private var isLoadingLoginState: Bool {
        if case .loadingLogin = state { return true }
        return false
    }
    private var loginCheck: ServerCheck? {
        if case let .logIn(check) = state {
            return check
        } else if case let .loadingLogin(check) = state {
            return check
        }
        return nil
    }

    @State private var uniqueName = true
    @State private var uniqueServer = true
    @State private var sourceNames: Set<String> = []
    @State private var existingServers: Set<String> = []

    enum Field: Int, Hashable {
        case name
        case server
        case username
        case password
    }
    @FocusState private var focusedField: Field?

    #if SUMI
    @Environment(\.dismiss) private var dismiss
    #else
    @EnvironmentObject private var path: NavigationCoordinator
    #endif

    init(
        icon: Image,
        title: String,
        sourceName: String,
        info: String,
        learnMoreUrl: URL?,
        sourceKeyPrefix: String,
        useEmail: Bool,
        placeholderServer: String? = nil,
        demoServer: String? = nil,
        demoTitle: String? = nil,
        demoInfo: String? = nil,
        checkServer: @escaping (String) async -> ServerCheck,
        logIn: @escaping (String, URL, String, String) async -> Bool,
        apiKeyLogIn: ((String, URL, String) async -> Bool)? = nil,
        oidcLogIn: ((String, URL, [HTTPCookie]) async -> Bool)? = nil,
        noLogIn: ((String, URL) async -> Bool)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.sourceName = sourceName
        self.info = info
        self.learnMoreUrl = learnMoreUrl
        self.sourceKeyPrefix = sourceKeyPrefix
        self.useEmail = useEmail
        self.placeholderServer = placeholderServer ?? demoServer
        self.demoServer = demoServer
        self.demoTitle = demoTitle
        self.demoInfo = demoInfo
        self.checkHandler = checkServer
        self.logInHandler = logIn
        self.apiKeyLogInHandler = apiKeyLogIn
        self.oidcLogInHandler = oidcLogIn
        self.noLogInHandler = noLogIn
    }

    var body: some View {
        let isLoading = state == .loading || isLoadingLoginState
        List {
            Section {
                SettingHeaderView(
                    icon: .raw(icon),
                    title: sourceName,
                    subtitle: info,
                    learnMoreUrl: learnMoreUrl
                )
            }

            Section {
                TextField(sourceName, text: $name)
                    .accessibilityIdentifier("SelfHosted.Name")
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focusedField, equals: .name)
                    .onSubmit { self.focusNextField($focusedField) }
                    .disabled(isLoading)
            } header: {
                Text(NSLocalizedString("SOURCE_NAME"))
            } footer: {
                if !uniqueName {
                    Text(NSLocalizedString("SOURCE_NAME_UNIQUE_ERROR"))
                        .foregroundStyle(.red)
                } else {
                    Text(NSLocalizedString("SOURCE_NAME_INFO"))
                }
            }
            Section {
                TextField(placeholderServer ?? NSLocalizedString("SERVER_URL"), text: $server)
                    .accessibilityIdentifier("SelfHosted.ServerURL")
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .server)
                    .onSubmit {
                        if !submitDisabled {
                            submit()
                        }
                    }
                    .submitLabel(.done)
                    .disabled(isLoading)
                    .onChange(of: server) { _ in
                        if isLogInState {
                            state = .initial
                        }
                    }
            } header: {
                Text(NSLocalizedString("SERVER_URL"))
            } footer: {
                if !uniqueServer {
                    Text(NSLocalizedString("SERVER_URL_UNIQUE_ERROR"))
                        .foregroundStyle(.red)
                } else {
                    Text(NSLocalizedString("SERVER_URL_INFO"))
                }
            }

            if let check = loginCheck {
                let hasMultipleLoginMethods = [check.canLoginBasic, check.canLoginApiKey, check.canLoginOIDC].filter({ $0 }).count > 1
                if hasMultipleLoginMethods {
                    Section(NSLocalizedString("LOGIN")) {
                        Picker(NSLocalizedString("LOGIN_METHOD"), selection: $loginMethod) {
                            if check.canLoginApiKey {
                                Text(NSLocalizedString("API_KEY")).tag(LoginMethod.apiKey)
                            }
                            if check.canLoginBasic {
                                Text(NSLocalizedString("BASIC")).tag(LoginMethod.basic)
                            }
                            if check.canLoginOIDC && check.oidcLoginURL != nil {
                                Text(NSLocalizedString("OIDC")).tag(LoginMethod.oidc)
                            }
                        }
                    }
                }
                if check.canLoginApiKey && (!hasMultipleLoginMethods || loginMethod == .apiKey) {
                    Section {
                        SecureField(NSLocalizedString("API_KEY"), text: $apiKey)
                            .accessibilityIdentifier("SelfHosted.APIKey")
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .onSubmit {
                                if !submitDisabled {
                                    submit()
                                }
                            }
                            .disabled(isLoading)
                    } header: {
                        if !hasMultipleLoginMethods {
                            Text(NSLocalizedString("LOGIN"))
                        }
                    }
                }
                if check.canLoginBasic && (!hasMultipleLoginMethods || loginMethod == .basic) {
                    Section {
                        Group {
                            if useEmail {
                                TextField(NSLocalizedString("EMAIL"), text: $username)
                                    .textContentType(.emailAddress)
                            } else {
                                TextField(NSLocalizedString("USERNAME"), text: $username)
                                    .textContentType(.username)
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($focusedField, equals: .username)
                        .onSubmit { self.focusNextField($focusedField) }
                        .disabled(isLoading)

                        SecureField(NSLocalizedString("PASSWORD"), text: $password)
                            .accessibilityIdentifier("SelfHosted.Password")
                            .textContentType(.password)
                            .submitLabel(.done)
                            .focused($focusedField, equals: .password)
                            .onSubmit {
                                if !submitDisabled {
                                    submit()
                                }
                            }
                            .disabled(isLoading)
                    } header: {
                        if !hasMultipleLoginMethods {
                            Text(NSLocalizedString("LOGIN"))
                        }
                    }
                }
                if check.canLoginOIDC && (!hasMultipleLoginMethods || loginMethod == .oidc), let loginURL = check.oidcLoginURL {
                    Section {
                        Button(NSLocalizedString("LOGIN_VIA_OIDC")) {
                            showLoginSheet = true
                        }
                        .sheet(isPresented: $showLoginSheet) {
                            OIDCLoginView(loginURL: loginURL) { cookies in
                                Task {
                                    await logIn(cookies: cookies)
                                }
                            }
                            .interactiveDismissDisabled()
                        }
                    }
                }
            }

            if
                isLogInState || isLoadingLoginState,
                server == demoServer,
                let demoTitle,
                let demoInfo
            {
                Section {
                    LocalSetupView.infoView(
                        title: LocalizedStringKey(demoTitle),
                        subtitle: LocalizedStringKey(demoInfo)
                    )
                }
            }

            if let error {
                Section {
                    switch error {
                        case .connection:
                            LocalSetupView.infoView(
                                title: LocalizedStringKey(NSLocalizedString("SERVER_ERROR")),
                                subtitle: LocalizedStringKey(NSLocalizedString("SERVER_ERROR_CONNECTION")),
                                error: true
                            )
                        case .authorization:
                            LocalSetupView.infoView(
                                title: LocalizedStringKey(NSLocalizedString("SERVER_ERROR")),
                                subtitle: LocalizedStringKey(NSLocalizedString("SERVER_ERROR_AUTHENTICATION")),
                                error: true
                            )
                    }
                }
            }
        }
        .onChange(of: name) { _ in
            ensureUniqueName()
        }
        .onChange(of: server) { _ in
            ensureUniqueServer()
        }
        .animation(.default, value: state)
        .animation(.default, value: error)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    submit()
                } label: {
                    if #available(iOS 26.0, *) {
                        if isLoading {
                            ProgressView().progressViewStyle(.circular)
                        } else {
                            Text(NSLocalizedString("CONTINUE"))
                        }
                    } else {
                        ZStack(alignment: .trailing) {
                            if isLoading {
                                ProgressView().progressViewStyle(.circular)
                            }
                            Text(NSLocalizedString("CONTINUE"))
                                .opacity(isLoading ? 0 : 1) // fixes weird transition animation
                        }
                    }
                }
                .disabled(submitDisabled)
                .accessibilityIdentifier("SelfHosted.Continue")
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard sourceNames.isEmpty else { return }
            await loadInfo()
        }
    }

    var submitDisabled: Bool {
        server.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !uniqueName || !uniqueServer
            || state == .loading || isLoadingLoginState
            || (
                isLogInState && (
                    (loginMethod == .basic && (username.isEmpty || password.isEmpty))
                        || (loginMethod == .apiKey && apiKey.isEmpty)
                        || loginMethod == .oidc
                )
            )
    }

    func loadInfo() async {
        let sources = await SourceManager.shared.getSourceInfos(sorted: false)
        sourceNames = Set(sources.map { $0.name })

        // find unique default name
        var defaultName = sourceName
        var counter = 2
        while sourceNames.contains(defaultName) {
            defaultName = "\(sourceName) \(counter)"
            counter += 1
        }
        self.name = defaultName

        // store existing komga servers to check against for uniqueness
        let relatedSources = sources.filter({ $0.sourceId.hasPrefix(sourceKeyPrefix) })
        self.existingServers = Set(relatedSources.compactMap {
            UserDefaults.standard.string(forKey: "\($0.sourceId).server")
                .flatMap { SelfHostedServerURL($0)?.sourceString }
        })
    }

    func submit() {
        switch state {
            case .initial:
                Task {
                    await checkServer()
                }
            case .logIn:
                Task {
                    await logIn()
                }
            default:
                break
        }
    }

    func ensureUniqueName() {
        let name = name.trimmingCharacters(in: .whitespaces)
        uniqueName = !sourceNames.contains(name)
    }

    func ensureUniqueServer() {
        guard let address = SelfHostedServerURL(server) else {
            uniqueServer = true
            return
        }
        uniqueServer = !existingServers.contains(address.sourceString)
    }

    func checkServer() async {
        error = nil
        state = .loading

        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let address = SelfHostedServerURL(server) else {
            state = .initial
            error = .connection
            return
        }
        server = address.sourceString
        ensureUniqueName()
        ensureUniqueServer()
        guard uniqueName, uniqueServer, !name.isEmpty else {
            state = .initial
            return
        }

        let serverCheck = await checkHandler(server)

        guard serverCheck.hasLoginMethod else {
            state = .initial
            error = .connection
            return
        }

        if serverCheck.mustSkipLogin {
            await noLogIn() // todo: also have some sort of option for no login in the login view
            return
        }

        if serverCheck.canLoginApiKey {
            loginMethod = .apiKey
        } else if serverCheck.canLoginBasic {
            loginMethod = .basic
        } else {
            loginMethod = .oidc
        }

        state = .logIn(serverCheck)
    }

    func logIn(cookies: [HTTPCookie] = []) async {
        guard case let .logIn(check) = state else {
            return
        }
        error = nil
        state = .loadingLogin(check)

        // trim whitespace (again, in case name was changed)
        name = name.trimmingCharacters(in: .whitespaces)

        guard let serverURL = SelfHostedServerURL(server)?.url else {
            state = .logIn(check)
            error = .connection
            return
        }

        let didLogIn = if !cookies.isEmpty, let oidcLogInHandler {
            await oidcLogInHandler(name, serverURL, cookies)
        } else if loginMethod == .apiKey, let apiKeyLogInHandler {
            await apiKeyLogInHandler(name, serverURL, apiKey)
        } else {
            await logInHandler(name, serverURL, username, password)
        }

        guard didLogIn else {
            state = .logIn(check)
            error = .authorization
            return
        }

        #if SUMI
        dismiss()
        #else
        path.dismiss()
        #endif
    }

    func noLogIn() async {
        guard
            let serverURL = SelfHostedServerURL(server)?.url,
            let noLogInHandler
        else {
            state = .initial
            error = .connection
            return
        }

        let success = await noLogInHandler(name, serverURL)

        guard success else {
            state = .initial
            error = .connection
            return
        }

        #if SUMI
        dismiss()
        #else
        path.dismiss()
        #endif
    }
}
