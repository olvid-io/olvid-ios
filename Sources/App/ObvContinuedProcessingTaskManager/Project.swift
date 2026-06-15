import ProjectDescription
import ProjectDescriptionHelpers


let name = "ObvContinuedProcessingTaskManager"


// MARK: - Targets

private let frameworkTarget = Target.makeFrameworkTarget(
    name: name,
    resources: [
        "Resources/Localizable.xcstrings",
    ],
    dependencies: [
        .Olvid.App.obvAppCoreConstants,
    ]
)


// MARK: - Project

let project = Project.createProjectForFramework(
    frameworkTarget: frameworkTarget,
    frameworkTestsTarget: nil)
