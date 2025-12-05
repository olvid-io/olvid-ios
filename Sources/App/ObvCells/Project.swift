import ProjectDescription
import ProjectDescriptionHelpers


let name = "ObvCells"


// MARK: - Targets

private let frameworkTarget = Target.makeFrameworkTarget(
    name: name,
    resources: [
        "Resources/Localizable.xcstrings",
        //"DevelopmentResources/DevelopmentAssets.xcassets",
    ],
    developmentAssets: "DevelopmentResources",
    dependencies: [
        .Olvid.App.obvSystemIcon,
        .Olvid.App.obvDesignSystem,
        .Olvid.App.obvAppTypes,
        .Olvid.App.obvProfilePictureBarButtonItem,
        .Olvid.App.UI.obvCircleAndTitlesView,
        .Olvid.App.UI.obvPhotoButton,
        .Olvid.Shared.obvTypes,
    ],
    enableSwift6: true)


// MARK: - Project

let project = Project.createProjectForFramework(
    frameworkTarget: frameworkTarget,
    frameworkTestsTarget: nil)
