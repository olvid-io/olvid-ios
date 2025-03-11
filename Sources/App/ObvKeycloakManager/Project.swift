import ProjectDescription
import ProjectDescriptionHelpers


// We use the "Xcode's default integration" way for including the AppAuth package.
// See https://docs.tuist.io/guides/develop/projects/dependencies#external-dependencies

let name = "ObvKeycloakManager"


// MARK: - Targets

private let frameworkTarget = Target.makeFrameworkTarget(
    name: name,
    resources: [
        "Resources/Localizable.xcstrings",
    ],
    dependencies: [
        .package(product: "AppAuth"),
        .Olvid.App.obvAppCoreConstants,
        .Olvid.Shared.obvTypes,
        .Olvid.Shared.olvidUtils,
        .Olvid.Engine.obvJWS,
        .Olvid.Shared.obvNetworkStatus,
    ])


// MARK: - Project

let project = Project.createProjectForFramework(
    packages: [
        //.remote(url: "https://github.com/olvid-io/AppAuth-iOS-for-Olvid", requirement: .branch("targetfix")),
        .remote(url: "https://github.com/openid/AppAuth-iOS", requirement: .exact(.init(1, 7, 5))),
    ],
    frameworkTarget: frameworkTarget,
    frameworkTestsTarget: nil)
