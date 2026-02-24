import SwiftUI

enum FolderSortOrder: String, CaseIterable {
    case name = "Name"
    case kind = "Kind"
    case dateModified = "Date Modified"
}

struct ContentView: View {
    @EnvironmentObject private var state: AppState
    @State private var pathInput: String = ""
    @State private var searchInput: String = ""
    @State private var newTagLabel: String = ""
    @State private var newTagColor: String = "#FF9F0A"
    @State private var profileName: String = ""
    @State private var profileCommand: String = ""
    @State private var profileWorkingDir: String = ""
    @State private var profileTerminal: TerminalLauncher.TerminalKind = .terminal
    @State private var profileWindows: Int = 1
    @State private var folderSort: FolderSortOrder = .name
    @State private var folderSortAscending: Bool = true

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            mainPane
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            pathInput = state.currentPath
        }
        .onChange(of: state.currentPath) { newValue in
            pathInput = newValue
        }
    }

    private var sidebar: some View {
        List {
            Section("Favorites") {
                if state.favorites.isEmpty {
                    Text("No favorites yet").foregroundStyle(.secondary)
                }
                ForEach(state.favorites, id: \.self) { path in
                    HStack {
                        Button(action: { state.jump(to: path) }) {
                            Label(path.lastPathComponent, systemImage: "star.fill")
                                .labelStyle(.titleAndIcon)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            state.removeFavorite(path)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            Section("Recents") {
                if state.recents.isEmpty {
                    Text("No recent folders yet").foregroundStyle(.secondary)
                }
                ForEach(state.recents) { entry in
                    Button(action: { state.jump(to: entry.path) }) {
                        VStack(alignment: .leading) {
                            Text(entry.path.lastPathComponent)
                            Text(entry.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Projects") {
                if state.projects.isEmpty {
                    Text("No project markers found").foregroundStyle(.secondary)
                }
                ForEach(state.projects) { project in
                    Button(action: { state.jump(to: project.path) }) {
                        VStack(alignment: .leading) {
                            Text(project.path.lastPathComponent)
                            Text(project.marker)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Tags") {
                if state.tagsForCurrentPath.isEmpty {
                    Text("Tag this folder to group it later").foregroundStyle(.secondary)
                }
                ForEach(state.tagsForCurrentPath) { tag in
                    HStack {
                        Circle()
                            .fill(Color(hex: tag.color))
                            .frame(width: 10, height: 10)
                        Text(tag.tag)
                        Spacer()
                        Button {
                            state.removeTag(tag)
                        } label: {
                            Image(systemName: "xmark.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Label", text: $newTagLabel)
                    HStack {
                        TextField("#RRGGBB", text: $newTagColor)
                            .frame(width: 90)
                        Button("Add Tag") {
                            guard !newTagLabel.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                            state.addTag(label: newTagLabel, color: newTagColor)
                            newTagLabel = ""
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .frame(minWidth: 280)
    }

    private var mainPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                pathBar
                searchBar
                launcherControls
                if let error = state.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
            .padding()
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    entriesList
                    profilesPanel
                }
                .padding()
            }
        }
    }

    private var pathBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("/path/to/folder", text: $pathInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        state.jump(to: pathInput)
                    }
                Button("Go") {
                    state.jump(to: pathInput)
                }
                Button(action: { state.favorite(state.currentPath) }) {
                    Label("Favorite", systemImage: "star")
                }
                Menu("Clipboard") {
                    Button("Copy Path") { state.copyPathToClipboard() }
                    Button("Copy cd Command") { state.copyCDCommand() }
                }
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            TextField("Search inside \(state.currentPath.lastPathComponent)", text: $searchInput)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    state.searchQuery = searchInput
                    state.performSearch()
                }
            Button("Search") {
                state.searchQuery = searchInput
                state.performSearch()
            }
        }
    }

    private var launcherControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Terminal", selection: $state.selectedTerminal) {
                    ForEach(TerminalLauncher.TerminalKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                Stepper(value: $state.windowCount, in: 1...5) {
                    Text("\(state.windowCount) window(s)")
                }
            }
            Button {
                state.openTerminal(path: state.currentPath)
            } label: {
                Label("Open Terminal Here", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var sortedEntries: [DirectoryEntry] {
        let order: (DirectoryEntry, DirectoryEntry) -> Bool
        switch folderSort {
        case .name:
            order = { folderSortAscending ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : $0.name.localizedStandardCompare($1.name) == .orderedDescending }
        case .kind:
            order = {
                let k0 = $0.sortKind
                let k1 = $1.sortKind
                if k0 != k1 { return folderSortAscending ? k0 < k1 : k0 > k1 }
                return folderSortAscending ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : $0.name.localizedStandardCompare($1.name) == .orderedDescending
            }
        case .dateModified:
            order = {
                let d0 = $0.modificationDate ?? .distantPast
                let d1 = $1.modificationDate ?? .distantPast
                if d0 != d1 { return folderSortAscending ? d0 < d1 : d0 > d1 }
                return folderSortAscending ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : $0.name.localizedStandardCompare($1.name) == .orderedDescending
            }
        }
        return state.entries.sorted(by: order)
    }

    private var entriesList: some View {
        List {
            if !state.searchResults.isEmpty {
                Section("Quick Search") {
                    ForEach(state.searchResults) { result in
                        Button(action: { state.jump(to: result.path) }) {
                            VStack(alignment: .leading) {
                                Text(result.name)
                                Text(result.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            Section(header: VStack(alignment: .leading, spacing: 6) {
                Text("Folder Contents")
                HStack(spacing: 12) {
                    Picker("Sort by", selection: $folderSort) {
                        ForEach(FolderSortOrder.allCases, id: \.self) { order in
                            Text(order.rawValue).tag(order)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 160)
                    Button {
                        folderSortAscending.toggle()
                    } label: {
                        Image(systemName: folderSortAscending ? "arrow.up" : "arrow.down")
                    }
                    .help(folderSortAscending ? "Ascending" : "Descending")
                    Spacer()
                }
            }) {
                ForEach(sortedEntries) { entry in
                    Button(action: { state.navigate(to: entry) }) {
                        HStack {
                            Image(systemName: entry.isDirectory ? "folder" : "doc")
                            VStack(alignment: .leading) {
                                Text(entry.name)
                                Text(entry.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if entry.isDirectory {
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(minHeight: 320)
    }

    private var profilesPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Launch Profiles")
                    .font(.headline)
                Spacer()
                Button("Reset Form") {
                    profileName = ""
                    profileCommand = ""
                    profileWorkingDir = ""
                    profileTerminal = state.selectedTerminal
                    profileWindows = 1
                }
                .buttonStyle(.bordered)
            }
            if state.profiles.isEmpty {
                Text("Save repetitive commands as profiles to launch them instantly.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(state.profiles) { profile in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(profile.name).fontWeight(.semibold)
                            if let command = profile.command {
                                Text(command).font(.caption).foregroundStyle(.secondary)
                            }
                            Text(profile.workingDir ?? state.currentPath)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Run") {
                            state.runProfile(profile)
                        }
                        Button(role: .destructive) {
                            state.deleteProfile(profile)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(8)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("New Profile")
                    .font(.subheadline)
                TextField("Name", text: $profileName)
                TextField("Command (optional)", text: $profileCommand)
                TextField("Working Directory (optional)", text: $profileWorkingDir)
                HStack {
                    Picker("Terminal", selection: $profileTerminal) {
                        ForEach(TerminalLauncher.TerminalKind.allCases) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    Stepper(value: $profileWindows, in: 1...5) {
                        Text("\(profileWindows) window(s)")
                    }
                }
                Button("Save Profile") {
                    guard !profileName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    state.saveProfile(
                        name: profileName,
                        command: profileCommand.isEmpty ? nil : profileCommand,
                        workingDir: profileWorkingDir.isEmpty ? nil : profileWorkingDir,
                        terminal: profileTerminal,
                        windows: profileWindows
                    )
                    profileName = ""
                    profileCommand = ""
                    profileWorkingDir = ""
                    profileWindows = 1
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

private extension String {
    var lastPathComponent: String {
        (self as NSString).lastPathComponent
    }
}

private extension Color {
    init(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).trimmingCharacters(in: .whitespaces)
        var int: UInt64 = 0
        Scanner(string: value).scanHexInt64(&int)
        let r, g, b: Double
        switch value.count {
        case 3:
            r = Double((int >> 8) & 0xF) / 15
            g = Double((int >> 4) & 0xF) / 15
            b = Double(int & 0xF) / 15
        case 6:
            r = Double((int >> 16) & 0xFF) / 255
            g = Double((int >> 8) & 0xFF) / 255
            b = Double(int & 0xFF) / 255
        default:
            r = 0.04; g = 0.52; b = 1.0
        }
        self = Color(red: r, green: g, blue: b)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState(coreClient: FallbackCoreClient()))
}
