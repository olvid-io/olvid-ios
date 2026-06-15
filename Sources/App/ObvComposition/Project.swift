import ProjectDescription
import ProjectDescriptionHelpers


let name = "ObvComposition"


// MARK: - Targets

private let frameworkTarget = Target.makeFrameworkTarget(
    name: name,
    resources: [
        "Resources/Localizable.xcstrings",
    ],
    developmentAssets: "DevelopmentResources",
    dependencies: [
        .Olvid.App.obvAppCoreConstants,
        .Olvid.App.obvAppTypes,
        .Olvid.App.obvDesignSystem,
        .Olvid.App.obvSystemIcon,
        .Olvid.Shared.obvTypes,
        .Olvid.App.obvSettings
    ],
    enableSwift6: true)


// MARK: - Project

let project = Project.createProjectForFramework(
    frameworkTarget: frameworkTarget,
    frameworkTestsTarget: nil)
