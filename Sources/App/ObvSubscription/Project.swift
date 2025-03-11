import ProjectDescription
import ProjectDescriptionHelpers


// We use the "Xcode's default integration" way for including the AppAuth package.
// See https://docs.tuist.io/guides/develop/projects/dependencies#external-dependencies

let name = "ObvSubscription"


// MARK: - Targets

private let frameworkTarget = Target.makeFrameworkTarget(
    name: name,
    resources: [
        "Resources/Localizable.xcstrings",
    ],
    dependencies: [
        .Olvid.App.obvUI,
        .Olvid.Shared.obvTypes,
    ])


// MARK: - Project

let project = Project.createProjectForFramework(
    frameworkTarget: frameworkTarget,
    frameworkTestsTarget: nil)
