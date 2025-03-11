import ProjectDescription
import ProjectDescriptionHelpers


let name = "ObvBigInt"


// MARK: - Targets

private let frameworkTarget = Target.makeFrameworkTarget(
    name: name,
    dependencies: [
        .package(product: "GMP"),
    ],
    prepareForSwift6: true)

private let frameworkTestsTarget = Target.makeFrameworkUnitTestsTarget(
    forTesting: frameworkTarget)


// MARK: - Project

let project = Project.createProjectForFramework(
    packages: [
        .package(path: .relativeToRoot("ExternalDependencies/Packages")),
    ],
    frameworkTarget: frameworkTarget,
    frameworkTestsTarget: frameworkTestsTarget)
