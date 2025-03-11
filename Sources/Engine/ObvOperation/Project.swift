import ProjectDescription
import ProjectDescriptionHelpers


let name = "ObvOperation"


// MARK: - Targets

private let frameworkTarget = Target.makeFrameworkTarget(
    name: name,
    dependencies: [
        .Olvid.Engine.obvCrypto,
        .Olvid.Shared.obvTypes,
    ])


// MARK: - Project

let project = Project.createProjectForFramework(
    frameworkTarget: frameworkTarget,
    frameworkTestsTarget: nil)
