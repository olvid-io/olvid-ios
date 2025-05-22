import ProjectDescription
import ProjectDescriptionHelpers


let name = "ObvUI"


// MARK: - Targets

private let frameworkTarget = Target.makeFrameworkTarget(
    name: name,
    resources: [
        "Resources/Localizable.xcstrings",
    ],
    dependencies: [
        .Olvid.App.obvDesignSystem,
        .Olvid.App.obvSettings,
        .Olvid.Shared.obvTypes,
        .Olvid.App.UI.obvCircledInitials,
        .Olvid.App.obvSystemIcon,
        .Olvid.App.obvUICoreData,
        .Olvid.App.obvAppCoreConstants
    ])


// MARK: - Project

let project = Project.createProjectForFramework(
    frameworkTarget: frameworkTarget,
    frameworkTestsTarget: nil)
