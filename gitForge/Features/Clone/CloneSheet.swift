import SwiftUI

/// "Clone a repository" (artboard `Welcome`): URL with its reachability,
/// GitHub / GitLab repos of the connected accounts, destination and the
/// identity profile for the new repo. Shows progress while cloning and
/// closes once the clone opens; a failure is shown here and keeps the form.
struct CloneSheet: View {
    let request: CloneRequest

    @Environment(AppState.self) private var appState
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    @AppStorage("gitForge.clone.lastParentDir") private var lastParentDir: String = ""
    @State private var model: CloneSheetModel?
    @State private var source: CloneRequest.Source = .url
    @State private var started = false

    private typealias Source = CloneRequest.Source

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s16) {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                Text("Clone a repository").textRole(.headline)
                Text("Paste a URL, or pick from your GitHub and GitLab accounts.")
                    .textRole(.callout)
                    .foregroundStyle(theme.colors.textSecondary)
            }
            Picker("Source", selection: $source) {
                Text("URL").tag(Source.url)
                Text("GitHub").tag(Source.github)
                Text("GitLab").tag(Source.gitlab)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .disabled(isCloning)

            if let model {
                switch source {
                case .url: form(model)
                case .github: picker(.github, model)
                case .gitlab: picker(.gitlab, model)
                }
            }
        }
        .padding(.horizontal, Spacing.s24)
        .padding(.top, Spacing.s24)
        .padding(.bottom, Spacing.s20)
        .frame(width: 560)
        .onAppear(perform: makeModel)
        // The cloned repo opened: done.
        .onChange(of: appState.catalog.activeRepository?.url) { _, _ in
            if started { dismiss() }
        }
        .onChange(of: appState.clone.isCloning) { _, cloning in
            if !cloning { started = false }
        }
        // One sheet per window: while this one is up it presents the
        // account / instance sheets and the error alert itself.
        .requestSheets()
        .errorAlert()
    }

    private var isCloning: Bool { appState.clone.isCloning }

    // MARK: URL form

    @ViewBuilder
    private func form(_ model: CloneSheetModel) -> some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: Spacing.s16) {
            field("Repository URL") {
                TextField("Paste an HTTPS or SSH repository URL", text: $model.url)
                    .textFieldStyle(.roundedBorder)
                    .textRole(.mono)
                    .overlay(alignment: .trailing) { probeBadge(model.probe).padding(.trailing, Spacing.s8) }
                    .task(id: model.url) { await model.urlChanged() }
                    .accessibilityLabel("Repository URL")
                    .accessibilityValue(Self.probeDescription(model.probe).map { "\(model.url), \($0)" } ?? model.url)
                if let summary = model.remoteSummary {
                    Text(summary).textRole(.caption).foregroundStyle(theme.colors.textSecondary)
                } else if let suggestion = RemoteHost.suggestedInstance(forRemoteURL: model.url,
                                                                        instances: appState.accounts.instances) {
                    Button("Add \(suggestion.host) as a \(suggestion.kind.label) instance…") {
                        appState.ui.addInstanceRequest = AddInstanceRequest(kind: suggestion.kind, url: "https://\(suggestion.host)")
                    }
                    .buttonStyle(.link)
                    .textRole(.caption)
                }
            }
            field("Clone into") {
                HStack(spacing: Spacing.s8) {
                    TextField("~/Developer/repo", text: $model.destination)
                        .textFieldStyle(.roundedBorder)
                        .textRole(.mono)
                    Button("Choose…") { Task { await choose(model) } }
                }
                if let hint = model.destinationHint {
                    Text(hint)
                        .textRole(.caption)
                        .foregroundStyle(model.canClone ? theme.colors.textSecondary : theme.colors.del)
                }
            }
            HStack(spacing: Spacing.s24) {
                Picker("Profile", selection: $model.profileId) {
                    Text("Keep global identity").tag(UUID?.none)
                    ForEach(appState.profiles.profiles) { profile in
                        Text(profile.name).tag(UUID?.some(profile.id))
                    }
                }
                .fixedSize()
                TextField("Branch (optional)", text: $model.branch)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
            }
            .textRole(.callout)
            HStack(spacing: Spacing.s24) {
                Toggle("Latest commit only", isOn: $model.options.shallow)
                    .help("Shallow clone (git clone --depth 1): faster, but History shows only the newest commit until you fetch more")
                Toggle("Include submodules", isOn: $model.options.submodules)
                    .help("Also clone the repository's submodules (--recurse-submodules)")
            }
            .toggleStyle(.checkbox)
            .textRole(.callout)
            .disabled(isCloning)
            if case let .running(stage, percent) = appState.clone.cloneState {
                VStack(alignment: .leading, spacing: Spacing.s4) {
                    HStack {
                        Text(stage).textRole(.monoSmall).foregroundStyle(theme.colors.textSecondary)
                        Spacer()
                        Text("\(Int(percent * 100))%").textRole(.monoSmall).monospacedDigit()
                    }
                    ProgressView(value: percent).progressViewStyle(.linear).tint(theme.colors.accent)
                }
            }
            HStack(spacing: Spacing.s8) {
                Spacer()
                Button("Cancel") {
                    if isCloning { appState.clone.cancel() } else { dismiss() }
                }
                .keyboardShortcut(.cancelAction)
                Button(isCloning ? "Cloning…" : "Clone") { clone(model) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isCloning || !model.canClone)
            }
            .controlSize(.large)
        }
    }

    @ViewBuilder
    private func probeBadge(_ state: CloneSheetModel.ProbeState) -> some View {
        switch state {
        case .idle:
            EmptyView()
        case .checking:
            Label("Checking…", systemImage: "ellipsis")
                .labelStyle(.titleAndIcon)
                .textRole(.caption)
                .foregroundStyle(theme.colors.textTertiary)
        case .done(.reachable):
            Label("Reachable", systemImage: "checkmark")
                .textRole(.caption, weight: .semibold)
                .foregroundStyle(theme.colors.ok)
        case .done(.unreachable(let failure)):
            Label(Self.reason(failure), systemImage: "xmark")
                .textRole(.caption, weight: .semibold)
                .foregroundStyle(theme.colors.del)
                .help("gitForge couldn't read this repository. You can still try to clone it.")
        }
    }

    /// The badge's text, for VoiceOver (the badge sits in an overlay of
    /// the field and isn't read on its own).
    nonisolated static func probeDescription(_ state: CloneSheetModel.ProbeState) -> String? {
        switch state {
        case .idle: nil
        case .checking: "Checking…"
        case .done(.reachable): "Reachable"
        case .done(.unreachable(let failure)): reason(failure)
        }
    }

    /// A short reason for "Can't reach".
    nonisolated static func reason(_ failure: RemoteFailure?) -> String {
        switch failure {
        case .authenticationHTTPS, .authenticationSSH, .accountRejected: "Can't reach · credentials"
        case .network: "Can't reach · offline"
        case .sslCertificate: "Can't reach · certificate"
        default: "Can't reach"
        }
    }

    // MARK: GitHub / GitLab

    private func picker(_ kind: HostingInstance.Kind, _ model: CloneSheetModel) -> some View {
        ScrollView {
            RemoteRepoPicker(kind: kind) { repo, accountId in
                model.pick(repo, accountId: accountId)
                source = .url
            }
            .padding(.vertical, Spacing.s4)
        }
        .frame(height: 380)
    }

    // MARK: Actions

    private func makeModel() {
        guard model == nil else { return }
        let credentials = appState.gitCredentials
        let parent = lastParentDir.isEmpty ? ("~/Developer" as NSString).expandingTildeInPath : lastParentDir
        let profiles = appState.profiles
        let made = CloneSheetModel(store: appState.accounts, parentDirectory: parent,
                                   probe: { url in await RemoteProbe.run(url: url, credentials: credentials) },
                                   profileExists: { id in profiles.profiles.contains { $0.id == id } })
        if let initial = request.initialURL { made.url = initial }
        source = request.source
        model = made
    }

    private func choose(_ model: CloneSheetModel) async {
        guard let parent = await appState.pickDirectoryPath(prompt: "Choose parent directory") else { return }
        lastParentDir = parent
        model.chooseParent(parent)
    }

    private func clone(_ model: CloneSheetModel) {
        let parent = (model.destination as NSString).deletingLastPathComponent
        if !parent.isEmpty { lastParentDir = parent }
        started = true
        appState.startClone(url: model.url, path: model.destination,
                            branch: model.branch.isEmpty ? nil : model.branch,
                            options: model.options,
                            accountId: model.accountIdForClone, profileId: model.profileId)
    }

    private func field<C: View>(_ label: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s6) {
            Text(label).textRole(.callout, weight: .semibold)
            content()
        }
    }
}

#Preview {
    CloneSheet(request: CloneRequest())
        .previewAppState(.preview)
}
