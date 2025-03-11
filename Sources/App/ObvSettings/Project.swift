import ProjectDescription
import ProjectDescriptionHelpers


let name = "ObvSettings"


// MARK: - Targets

private let frameworkTarget = Target.makeFrameworkTarget(
    name: name,
    resources: [
        "Resources/Localizable.xcstrings",
    ],
    dependencies: [
        .Olvid.Shared.obvTypes,
        .Olvid.App.obvDesignSystem,
        .Olvid.App.ObvUserNotifications.sounds,
        .Olvid.App.obvAppCoreConstants,
    ])


// MARK: - Project

let project = Project.createProjectForFramework(
    frameworkTarget: frameworkTarget,
    frameworkTestsTarget: nil)
