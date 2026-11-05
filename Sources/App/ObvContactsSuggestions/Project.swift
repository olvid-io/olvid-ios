import ProjectDescription
import ProjectDescriptionHelpers


let name = "ObvContactsSuggestions"


// MARK: - Targets

private let frameworkTarget = Target.makeFrameworkTarget(
    name: name,
    resources: [
        "Resources/Localizable.xcstrings",
    ],
    developmentAssets: "DevelopmentResources",
    dependencies: [
        .Olvid.App.obvSystemIcon,
        .Olvid.App.obvDesignSystem,
        .Olvid.Shared.obvTypes,
    ],
    enableSwift6: true)


private let frameworkTestsTarget = Target.makeFrameworkUnitTestsTarget(forTesting: frameworkTarget)


// MARK: - Project

let project = Project.createProjectForFramework(
    frameworkTarget: frameworkTarget,
    frameworkTestsTarget: frameworkTestsTarget)
