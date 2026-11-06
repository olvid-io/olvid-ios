import ProjectDescription
import ProjectDescriptionHelpers


let name = "ObvMediaTranscoding"


// MARK: - Targets

private let frameworkTarget = Target.makeFrameworkTarget(
    name: name,
    dependencies: [
        .Olvid.Engine.obvCrypto,
        .Olvid.Shared.olvidUtils,
        .Olvid.App.obvAppTypes,
        .Olvid.App.obvAppCoreConstants,
    ])


private let frameworkTestsTarget = Target.makeFrameworkUnitTestsTarget(
    forTesting: frameworkTarget)


// MARK: - Project

let project = Project.createProjectForFramework(
    frameworkTarget: frameworkTarget,
    frameworkTestsTarget: frameworkTestsTarget)
