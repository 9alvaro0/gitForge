import SwiftUI

/// "Clone a repository" (artboard `Welcome`): URL with its reachability,
/// GitHub / GitLab repos of the connected accounts, destination and the
/// identity profile for the new repo. Shows progress while cloning and
/// closes when the clone ends (a failure is reported by the app's alert).
struct CloneSheet: View {
    let request: CloneRequest

    @Environment(AppState.self) private var appState
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    @AppStorage("gitForge.clone.lastParentDir") private var lastParentDir: String = ""
    @State private var model: CloneSheetModel?
    @State private var source: Source = .url
    @State private var started = false

    enum Source: Hashable { case url, github, gitlab }

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
        .onChange(of: appState.clone.isCloning) { _, cloning in
            if started, !cloning { dismiss() }
        }
    }

    private var isCloning: Bool { appState.clone.isCloning }

    // MARK: URL form

    @ViewBuilder
    private func form(_ model: CloneSheetModel) -> some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: Spacing.s16) {
            field("Repository URL") {
                TextField("git@github.com:owner/repo.git", text: $model.url)
                    .textFieldStyle(.roundedBorder)
                    .textRole(.mono)
                    .overlay(alignment: .trailing) { probeBadge(model.probe).padding(.trailing, Spacing.s8) }
                    .task(id: model.url) { await model.urlChanged() }
                    .accessibilityLabel("Repository URL")
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

    /// A short reason for "Can't reach".
    static func reason(_ failure: RemoteFailure?) -> String {
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
        let made = CloneSheetModel(store: appState.accounts, parentDirectory: parent,
                                   probe: { url in await RemoteProbe.run(url: url, credentials: credentials) })
        if let initial = request.initialURL { made.url = initial }
        model = made
    }

    private func choose(_ model: CloneSheetModel) async {
        guard let parent = await appState.pickDirectoryPath(prompt: "Choose parent directory") else { return }
        model.destination = "\(parent)/\(CloneSheetModel.repoName(from: model.url) ?? "repo")"
    }

    private func clone(_ model: CloneSheetModel) {
        let parent = (model.destination as NSString).deletingLastPathComponent
        if !parent.isEmpty { lastParentDir = parent }
        started = true
        appState.startClone(url: model.url, path: model.destination,
                            branch: model.branch.isEmpty ? nil : model.branch,
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
