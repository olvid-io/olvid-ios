import ProjectDescription
import ProjectDescriptionHelpers

let dependencies = Dependencies(
    carthage: .init(TargetDependency.CarthageDependency.allCases),
    swiftPackageManager: .init(TargetDependency.SPMDependency.allCases),
    platforms: [.iOS]
)
