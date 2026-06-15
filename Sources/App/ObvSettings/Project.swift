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
        .Olvid.App.obvAppTypes,
        .Olvid.App.ObvUserNotifications.sounds,
        .Olvid.App.obvAppCoreConstants,
        .Olvid.App.obvSystemIcon,
    ])


// MARK: - Project

let project = Project.createProjectForFramework(
    frameworkTarget: frameworkTarget,
    frameworkTestsTarget: nil)
