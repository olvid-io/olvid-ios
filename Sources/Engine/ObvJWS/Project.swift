import ProjectDescription
import ProjectDescriptionHelpers

// We use the "Xcode's default integration" way for including the JOSESwift package.
// See https://docs.tuist.io/guides/develop/projects/dependencies#external-dependencies

let name = "ObvJWS"


// MARK: - Targets

private let frameworkTarget = Target.makeFrameworkTarget(
    name: name,
    dependencies: [
        .Olvid.Engine.obvEncoder,
        .Olvid.Shared.olvidUtils,
        .package(product: "JOSESwift"),
    ])


// MARK: - Project

let project = Project.createProjectForFramework(
    packages: [
        //.remote(url: "https://github.com/olvid-io/JOSESwift-for-Olvid", requirement: .branch("targetfix")),
        .remote(url: "https://github.com/airsidemobile/JOSESwift", requirement: .exact(.init(3, 0, 0))),
    ],
    frameworkTarget: frameworkTarget,
    frameworkTestsTarget: nil)
