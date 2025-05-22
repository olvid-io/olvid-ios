import ProjectDescription
import ProjectDescriptionHelpers


let name = "ObvAppTypes"


// MARK: - Targets

private let frameworkTarget = Target.makeFrameworkTarget(
    name: name,
    resources: [],
    dependencies: [
        .Olvid.App.obvAppCoreConstants,
        .Olvid.Shared.obvTypes,
        .Olvid.Engine.obvCrypto,
        .Olvid.Engine.obvEncoder,
    ])

private let frameworkTestsTarget = Target.makeFrameworkUnitTestsTarget(
    forTesting: frameworkTarget)

// MARK: - Project

let project = Project.createProjectForFramework(
    frameworkTarget: frameworkTarget,
    frameworkTestsTarget: frameworkTestsTarget)
