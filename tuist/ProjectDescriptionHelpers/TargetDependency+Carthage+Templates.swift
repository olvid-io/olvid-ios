import ProjectDescription
import Foundation

public extension TargetDependency {
    enum CarthageDependency: CaseIterable {
        /// https://gitlab.com/Olvid/appauthiosmodifiedforolvid/-/tree/modified-for-olvid
        case appAuth

        public var dependency: CarthageDependencies.Dependency {
            switch self {
            case .appAuth:
                return .github(path: "https://github.com/olvid-io/AppAuth-iOS-for-Olvid.git", requirement: .branch("targetfix"))
            }
        }

        fileprivate var _productName: String {
            switch self {
            case .appAuth:
                return "AppAuth"
            }
        }
    }
}

public extension TargetDependency {
    init(_ carthageDependency: CarthageDependency) {
        self = .external(name: carthageDependency._productName)
    }
}

extension CarthageDependencies {
    public init(_ dependencies: [TargetDependency.CarthageDependency]) {
        let targetDependencies: [CarthageDependencies.Dependency] = dependencies
            .map(\.dependency)

        self.init(targetDependencies)
    }
}
