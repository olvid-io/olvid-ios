import ProjectDescription
import ProjectDescriptionHelpers


let name = "ObvAppBackup"


// MARK: - Targets

private let frameworkTarget = Target.makeFrameworkTarget(
    name: name,
    resources: [
        "Resources/Localizable.xcstrings",
        "Resources/Media.xcassets",
        "DevelopmentResources/DevelopmentAssets.xcassets",
    ],
    developmentAssets: "DevelopmentResources",
    dependencies: [
        .Olvid.Engine.obvCrypto,
        .Olvid.App.obvSystemIcon,
        .Olvid.App.obvDesignSystem,
        .Olvid.App.obvAppCoreConstants,
        .Olvid.App.obvAppTypes,
        .Olvid.Shared.obvTypes,
        .Olvid.App.ThirdParty.confettiSwiftUI
    ],
    enableSwift6: true)

// MARK: - Project

let project = Project.createProjectForFramework(
    frameworkTarget: frameworkTarget,
    frameworkTestsTarget: nil)
