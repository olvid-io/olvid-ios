import ProjectDescription
import ProjectDescriptionHelpers


let name = "ObvDesignSystem"


// MARK: - Targets

private let frameworkTarget = Target.makeFrameworkTarget(
    name: name,
    resources: [
        "Resources/AppThemeAssets.xcassets",
    ],
    dependencies: [
        .Olvid.Engine.obvCrypto,
        .Olvid.Shared.obvTypes,
        .Olvid.App.obvSystemIcon,
    ])


// MARK: - Project

let project = Project.createProjectForFramework(
    frameworkTarget: frameworkTarget,
    frameworkTestsTarget: nil)
