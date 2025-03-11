import ProjectDescription
import ProjectDescriptionHelpers


let name = "ObvCommunicationInteractor"


// MARK: - Targets

private let frameworkTarget = Target.makeFrameworkTarget(
    name: name,
    resources: [],
    dependencies: [
        .Olvid.Shared.obvTypes,
        .Olvid.App.obvAppTypes,
        .Olvid.App.obvSystemIcon,
        .Olvid.App.obvSettings,
        .Olvid.App.obvUICoreDataStructs,
    ])

// MARK: - Project

let project = Project.createProjectForFramework(
    frameworkTarget: frameworkTarget,
    frameworkTestsTarget: nil)
