import ProjectDescription
import Foundation

public extension TargetDependency {
    enum SPMDependency: CaseIterable {
        /// https://github.com/airsidemobile/JOSESwift
        case joseSwift

        /// local implementation of GMP
        case gmp

        /// https://github.com/apple/swift-collections
        case orderedCollections

        public var package: Package {
            switch self {
            case .joseSwift:
                return .remote(url: "https://github.com/airsidemobile/JOSESwift.git", requirement: .exact("2.4.0"))

            case .gmp:
                return .local(path: .relativeToRoot("tuist/GMPSPM"))

            case .orderedCollections:
                return .remote(url: "https://github.com/apple/swift-collections.git", requirement: .exact("1.0.4"))

            }
        }

        fileprivate var _productName: String {
            switch self {
            case .joseSwift:
                return "JOSESwift"

            case .gmp:
                return "GMP"

            case .orderedCollections:
                return "OrderedCollections"

            }
        }
    }
}

public extension TargetDependency {
    init(_ spmPackage: SPMDependency) {
        self = .external(name: spmPackage._productName)
    }
}

extension SwiftPackageManagerDependencies {
    public init(_ packages: [TargetDependency.SPMDependency]) {
        let uniquedPackages: [Package] = packages
            .map(\.package)
            .reduce(into: []) { accumulator, item in
            if !accumulator.contains(item) {
                accumulator.append(item)
            }
        }

        self.init(uniquedPackages,
                  baseSettings: .defaultSPMProjectSettings())
    }
}
