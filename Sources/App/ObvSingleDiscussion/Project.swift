import ProjectDescription
import ProjectDescriptionHelpers


let name = "ObvSingleDiscussion"


// MARK: - Targets

private let frameworkTarget = Target.makeFrameworkTarget(
    name: name,
    resources: [
        "Resources/Localizable.xcstrings",
        "DevelopmentResources/DevelopmentAssets.xcassets",
    ],
    developmentAssets: "DevelopmentResources",
    dependencies: [
        .Olvid.App.obvDesignSystem,
        .Olvid.App.obvLocation,
        .Olvid.App.obvPollFeature,
        .Olvid.App.obvAppCoreConstants,
        .Olvid.App.obvAppTypes,
        .Olvid.App.obvSystemIcon,
        .Olvid.App.UI.obvCircleAndTitlesView,
        .Olvid.App.Components.obvEmojiUtils,
        .Olvid.Shared.obvTypes,
        .Olvid.Shared.olvidUtils,
    ],
    enableSwift6: true)


// MARK: - Project

let project = Project.createProjectForFramework(
    frameworkTarget: frameworkTarget,
    frameworkTestsTarget: nil)
