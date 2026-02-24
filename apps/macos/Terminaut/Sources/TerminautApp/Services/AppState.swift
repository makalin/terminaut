import Foundation
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

@MainActor
final class AppState: ObservableObject {
    @Published var currentPath: String
    @Published var entries: [DirectoryEntry] = []
    @Published var favorites: [String] = []
    @Published var recents: [RecentEntry] = []
    @Published var projects: [ProjectRoot] = []
    @Published var errorMessage: String?
    @Published var selectedTerminal: TerminalLauncher.TerminalKind = .terminal
    @Published var windowCount: Int = 1
    @Published var tagsForCurrentPath: [TaggedPath] = []
    @Published var allTags: [TaggedPath] = []
    @Published var profiles: [LaunchProfile] = []
    @Published var searchQuery: String = ""
    @Published var searchResults: [SearchResult] = []

    private let coreClient: CoreClientProtocol
    private let launcher = TerminalLauncher()

    init(coreClient: CoreClientProtocol) {
        self.coreClient = coreClient
        self.currentPath = FileManager.default.homeDirectoryForCurrentUser.path
    }

    func bootstrap() {
        Task {
            await refreshAll(for: currentPath)
        }
    }

    func refreshAll(for path: String) async {
        await fetchState(for: path)
    }

    func navigate(to entry: DirectoryEntry) {
        Task {
            await refreshAll(for: entry.path)
        }
    }

    func jump(to path: String) {
        Task {
            await refreshAll(for: path)
        }
    }

    func favorite(_ path: String) {
        Task {
            do {
                try coreClient.addFavorite(path: path)
                try coreClient.touchRecent(path: path)
                await refreshAll(for: currentPath)
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    func removeFavorite(_ path: String) {
        Task {
            do {
                try coreClient.removeFavorite(path: path)
                await refreshAll(for: currentPath)
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    func addTag(label: String, color: String) {
        Task {
            do {
                try coreClient.addTag(path: currentPath, label: label, color: color)
                await refreshAll(for: currentPath)
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }

    func removeTag(_ tag: TaggedPath) {
        Task {
            do {
                try coreClient.removeTag(path: tag.path, label: tag.tag)
                await refreshAll(for: currentPath)
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }

    func saveProfile(id: UUID? = nil, name: String, command: String?, workingDir: String?, terminal: TerminalLauncher.TerminalKind?, windows: Int) {
        Task {
            do {
                _ = try coreClient.saveProfile(id: id, name: name, command: command, workingDir: workingDir, terminal: terminal?.rawValue, windows: windows)
                await refreshAll(for: currentPath)
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }

    func deleteProfile(_ profile: LaunchProfile) {
        Task {
            do {
                try coreClient.deleteProfile(id: profile.id)
                await refreshAll(for: currentPath)
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }

    func runProfile(_ profile: LaunchProfile) {
        Task {
            do {
                let destination = profile.workingDir ?? currentPath
                let preferredTerminal = profile.terminal.flatMap { TerminalLauncher.TerminalKind(rawValue: $0) } ?? selectedTerminal
                try launcher.open(kind: preferredTerminal, path: destination, windows: Int(max(1, Int(profile.windows))), command: profile.command)
                try coreClient.touchRecent(path: destination)
                await refreshAll(for: destination)
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }

    func openTerminal(path: String, command: String? = nil) {
        Task {
            do {
                try launcher.open(kind: selectedTerminal, path: path, windows: windowCount, command: command)
                try coreClient.touchRecent(path: path)
                await refreshAll(for: path)
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    func copyPathToClipboard() {
        writeToPasteboard(currentPath)
    }

    func copyCDCommand() {
        writeToPasteboard("cd \(currentPath)")
    }

    func performSearch() {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }
        Task {
            do {
                let results = try coreClient.search(start: currentPath, query: trimmed, limit: 25)
                await MainActor.run {
                    searchResults = results
                }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }

    private func fetchState(for path: String) async {
        do {
            let normalized = try coreClient.normalize(path: path)
            let entries = try coreClient.listDirectory(path: normalized)
            let favorites = try coreClient.listFavorites()
            let recents = try coreClient.listRecents()
            let projects = try coreClient.detectProjects(path: normalized)
            let tagsForPath = try coreClient.tags(for: normalized)
            let tagUniverse = try coreClient.listTags()
            let profiles = try coreClient.listProfiles()
            try coreClient.touchRecent(path: normalized)

            self.currentPath = normalized
            self.entries = entries
            self.favorites = favorites
            self.recents = recents
            self.projects = projects
            self.tagsForCurrentPath = tagsForPath
            self.allTags = tagUniverse
            self.profiles = profiles
            if !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                performSearch()
            } else {
                self.searchResults = []
            }
            self.errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func writeToPasteboard(_ string: String) {
        #if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        #endif
    }
}
