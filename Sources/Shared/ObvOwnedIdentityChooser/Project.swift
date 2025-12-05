import ProjectDescription
import ProjectDescriptionHelpers


let name = "ObvOwnedIdentityChooser"


// MARK: - Targets

private let frameworkTarget = Target.makeFrameworkTarget(
    name: name,
    resources: [
        "Resources/Localizable.xcstrings",
        //"DevelopmentResources/DevelopmentAssets.xcassets",
    ],
    developmentAssets: "DevelopmentResources",
    dependencies: [
        .Olvid.App.obvDesignSystem,
        .Olvid.App.obvSystemIcon,
        .Olvid.App.obvAppCoreConstants,
        .Olvid.Shared.obvTypes,
    ],
    enableSwift6: true)


// MARK: - Project

let project = Project.createProjectForFramework(
    frameworkTarget: frameworkTarget,
    frameworkTestsTarget: nil)
