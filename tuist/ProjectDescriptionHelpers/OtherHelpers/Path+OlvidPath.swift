import ProjectDescription

public enum OlvidSourceDirectory {
    case app
    case engine
    case shared
    var directoryName: String {
        switch self {
        case .app: return "App"
        case .engine: return "Engine"
        case .shared: return "Shared"
        }
    }
}


extension Path {
    
    public static func olvidPath(_ path: String, in sourceDirectory: OlvidSourceDirectory) -> ProjectDescription.Path {
        .relativeToRoot("Sources/\(sourceDirectory.directoryName)/\(path)")
    }

}
