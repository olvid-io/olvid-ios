import ProjectDescription
import Foundation

public extension TargetDependency {
    
    enum SPMDependency: CaseIterable {
        
        /// local implementation of GMP
        case gmp

        public var package: Package {
            switch self {

            case .gmp:
                return .local(path: .relativeToRoot("Tuist/GMPSPM"))

            }
        }

        fileprivate var _productName: String {
            switch self {

            case .gmp:
                return "GMP"

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

        /// Although this init is deprecated, we continue to use until Tuist documentation is updated
        /// See https://docs.tuist.io/guides/third-party-dependencies
        /// As of 2023-11-29, the document appears to be wrong.
        self.init(uniquedPackages,
                  baseSettings: .defaultSPMProjectSettings())
    }
}
