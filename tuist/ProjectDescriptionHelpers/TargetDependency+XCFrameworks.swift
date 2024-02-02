import ProjectDescription
import Foundation

public extension TargetDependency {
    enum XCFramework {
        case webRTC

        private var xcFrameworkName: String {
            switch self {
            case .webRTC:
                return "WebRTC.xcframework"
            }
        }

        fileprivate var path: Path {
            return .relativeToRoot("Tuist/xcframeworks/".appending(xcFrameworkName))
        }
    }
}

public extension TargetDependency {
    init(_ xcFramework: XCFramework) {
        self = .xcframework(path: xcFramework.path)
    }
}
