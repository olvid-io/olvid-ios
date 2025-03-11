import ProjectDescription
import ProjectDescriptionHelpers


let name = "ObvUICoreDataStructs"


// MARK: - Targets

private let frameworkTarget = Target.makeFrameworkTarget(
    name: name,
    resources: [],
    dependencies: [
        .Olvid.Shared.obvTypes,
        .Olvid.App.ObvUserNotifications.sounds,
        .Olvid.App.obvAppTypes,
    ]
)


// MARK: - Project

let project = Project.createProjectForFramework(
    frameworkTarget: frameworkTarget,
    frameworkTestsTarget: nil)
