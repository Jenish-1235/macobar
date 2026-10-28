import Foundation

/// Places on the Mac that Macie's file changes must leave alone, and private places that need the user's OK every time.
enum ProtectedLocations {
    /// Folders macOS and installed programs run from; changing them could break or subvert the Mac. `/.vol` reaches any file by number.
    private static let systemFolders = ["/System", "/Library", "/usr", "/bin", "/sbin", "/etc", "/var", "/private", "/opt", "/cores", "/dev", "/.vol"]
    /// The user's scratch folders inside the system folders, which stay changeable.
    private static let scratchFolders = ["/tmp", "/private/tmp", "/var/folders", "/private/var/folders"]
    /// Folders in the home folder that hold secrets, start code at login, or keep macobar's own memory, schedule and history.
    private static let protectedHomeFolders = ["Library/Keychains", "Library/LaunchAgents", "Library/Application Support/macobar", ".ssh"]
    /// Folders in the home Library that hold the user's own cloud documents (iCloud Drive, Dropbox and the like), so they aren't private.
    private static let documentLibraryFolders: Set = ["mobile documents", "cloudstorage"]

    /// Why changing (writing, moving, copying onto or trashing) `url` is refused, or nil when it may be changed.
    static func refusal(forChanging url: URL) -> String? {
        let home = homeComponents
        let ownFiles = ownFileComponents
        for path in candidateComponents(of: url) {
            if home.contains(where: { $0.starts(with: path) }) {
                return "\(url.path) is the home folder or one of its parents; Macie doesn't change it."
            }
            let isScratch = scratchFolders.contains { path.starts(with: components(of: $0)) }
            if !isScratch, systemFolders.contains(where: { path.starts(with: components(of: $0)) }) {
                return "\(url.path) is a macOS system location; Macie doesn't change files there."
            }
            // A protected folder's parents count too, since moving or trashing a parent takes the folder with it.
            if ownFiles.contains(where: { path.starts(with: $0) || $0.starts(with: path) }) {
                return "\(url.path) is a protected location (secrets, login items or macobar's own data); Macie doesn't change it."
            }
            if path.dropLast().contains(where: { $0.hasSuffix(".app") }) {
                return "\(url.path) is inside an app; Macie doesn't change apps' contents."
            }
        }
        return nil
    }

    /// Whether `url` is private: in the home Library (other than cloud documents) or hidden (such as ~/.ssh or ~/.zshrc), wherever the path reaches it from, so touching it asks every time.
    static func isPrivate(_ url: URL) -> Bool {
        let libraries = homeComponents.map { $0 + ["library"] }
        return candidateComponents(of: url).contains { path in
            path.contains { $0.hasPrefix(".") && $0 != ".trash" } || libraries.contains { isInPrivateLibrary(path, library: $0) }
        }
    }

    /// Whether `path` passes through `library` (the home Library, also when reached from another mount such as /System/Volumes/Data) other than into cloud documents.
    private static func isInPrivateLibrary(_ path: [String], library: [String]) -> Bool {
        guard path.count >= library.count else { return false }
        return (0...(path.count - library.count)).contains { start in
            let end = start + library.count
            guard Array(path[start..<end]) == library else { return false }
            return !(path.dropFirst(end).first.map(documentLibraryFolders.contains) ?? false)
        }
    }

    /// The home folder's lowercased components, as written and with links resolved.
    private static var homeComponents: [[String]] {
        let home = URL.homeDirectory
        return [components(of: home.standardizedFileURL.path), components(of: home.resolvingSymlinksInPath().path)]
    }

    /// The protected home folders, macobar's preferences file and its app bundle, as lowercased components.
    private static var ownFileComponents: [[String]] {
        let home = URL.homeDirectory
        var urls = protectedHomeFolders.map { home.appending(path: $0) }
        if let bundleID = Bundle.main.bundleIdentifier {
            urls.append(home.appending(path: "Library/Preferences/\(bundleID).plist"))
        }
        if Bundle.main.bundleURL.pathExtension.lowercased() == "app" { urls.append(Bundle.main.bundleURL) }
        return urls.flatMap { [components(of: $0.standardizedFileURL.path), components(of: $0.resolvingSymlinksInPath().path)] }
    }

    /// `url`'s lowercased components as written, and with the links in its deepest existing part resolved (links in paths that don't exist yet aren't resolved by Foundation).
    private static func candidateComponents(of url: URL) -> [[String]] {
        let standardized = url.standardizedFileURL
        return [standardized.path, resolvingExistingPart(of: standardized).path].map(components)
    }

    /// `url` with every link resolved up to its deepest existing folder or item, and the parts not created yet appended unchanged.
    private static func resolvingExistingPart(of url: URL) -> URL {
        var existing = url
        var missing: [String] = []
        while !FileManager.default.fileExists(atPath: existing.path), existing.pathComponents.count > 1 {
            missing.insert(existing.lastPathComponent, at: 0)
            existing.deleteLastPathComponent()
        }
        return missing.reduce(existing.resolvingSymlinksInPath()) { $0.appending(path: $1) }
    }

    /// `path` split into lowercased components, since the Mac's disk ignores case.
    private static func components(of path: String) -> [String] {
        (path as NSString).standardizingPath.lowercased().split(separator: "/").map(String.init)
    }
}
