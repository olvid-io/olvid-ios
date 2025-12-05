import ProjectDescription
import ProjectDescriptionHelpers


let name = "ObvAppNavigation"


// MARK: - Targets

private let frameworkTarget = Target.makeFrameworkTarget(
    name: name,
    resources: [
        "Resources/Localizable.xcstrings",
        //"DevelopmentResources/DevelopmentAssets.xcassets",
    ],
    //developmentAssets: "DevelopmentResources",
    dependencies: [
        .Olvid.App.obvSystemIcon,
        .Olvid.App.obvDesignSystem,
        .Olvid.App.obvAppTypes,
        .Olvid.App.UI.obvCircleAndTitlesView,
        .Olvid.App.UI.obvPhotoButton,
        .Olvid.Shared.obvTypes,
        .Olvid.App.obvUIGroupSharedBetweenV1AndV2,
        .Olvid.App.obvUIGroupV1,
        .Olvid.App.obvUIGroupV2,
        .Olvid.App.obvSingleContact,
    ],
    enableSwift6: true)


// MARK: - Project

let project = Project.createProjectForFramework(
    frameworkTarget: frameworkTarget,
    frameworkTestsTarget: nil)
