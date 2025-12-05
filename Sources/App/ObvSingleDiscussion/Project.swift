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
        .Olvid.App.obvAppCoreConstants,
        .Olvid.App.UI.obvCircleAndTitlesView,
        .Olvid.Shared.obvTypes,
    ],
    enableSwift6: true)


// MARK: - Project

let project = Project.createProjectForFramework(
    frameworkTarget: frameworkTarget,
    frameworkTestsTarget: nil)
