import ProjectDescription
import ProjectDescriptionHelpers


let name = "ObvDesignSystem"


// MARK: - Targets

private let frameworkTarget = Target.makeFrameworkTarget(
    name: name,
    resources: [
        "Resources/Localizable.xcstrings",
        "Resources/AppThemeAssets.xcassets",
        "DevelopmentResources/DevelopmentAssets.xcassets",
    ],
    developmentAssets: "DevelopmentResources",
    dependencies: [
        .package(product: "SwiftUIIntrospect"),
        .Olvid.Engine.obvCrypto,
        .Olvid.Shared.obvTypes,
        .Olvid.App.obvSystemIcon,
        .Olvid.App.obvAppCoreConstants,
    ]
)


// MARK: - Project

let project = Project.createProjectForFramework(
    frameworkTarget: frameworkTarget,
    frameworkTestsTarget: nil)
