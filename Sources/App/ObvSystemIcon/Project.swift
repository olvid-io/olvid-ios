import ProjectDescription
import ProjectDescriptionHelpers


let name = "ObvSystemIcon"


// MARK: - Targets

private let frameworkTarget = Target.makeFrameworkTarget(
    name: name,
    resources: [
        "Resources/Assets.xcassets",
    ],
    dependencies: [],
    prepareForSwift6: true)


// MARK: - Project

let project = Project.createProjectForFramework(
    frameworkTarget: frameworkTarget,
    frameworkTestsTarget: nil)
