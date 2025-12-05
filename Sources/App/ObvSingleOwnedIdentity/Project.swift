import ProjectDescription
import ProjectDescriptionHelpers


let name = "ObvSingleOwnedIdentity"


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
        .Olvid.App.obvLicenceActivationFlow,
        .Olvid.App.obvAppCoreConstants,
        .Olvid.App.obvAppTypes,
        .Olvid.App.obvSubscription,
        .Olvid.App.UI.obvCircleAndTitlesView,
        .Olvid.App.ThirdParty.confettiSwiftUI,
        .Olvid.Shared.olvidUtils,
        .Olvid.Shared.obvTypes,
        .Olvid.Engine.obvCrypto,
        //.Olvid.App.obvSystemIcon,
        //.Olvid.App.obvCells,
        //.Olvid.App.obvProfilePictureBarButtonItem,
        //.Olvid.App.UI.obvPhotoButton,
    ],
    enableSwift6: true)


// MARK: - Project

let project = Project.createProjectForFramework(
    frameworkTarget: frameworkTarget,
    frameworkTestsTarget: nil)
