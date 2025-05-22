import ProjectDescription
import ProjectDescriptionHelpers


let name = "ObvDesignSystem"


// MARK: - Targets

#warning("TODO: verifier que la technique avec developmentAssets marche bien. Mais le faire avec une autre target. Ici, ce n'est pas clair que ca marche")
private let frameworkTarget = Target.makeFrameworkTarget(
    name: name,
    resources: [
        "Resources/Localizable.xcstrings",
        "Resources/AppThemeAssets.xcassets",
        "DevelopmentResources/DevelopmentAssets.xcassets",
    ],
    developmentAssets: "DevelopmentResources",
    dependencies: [
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
