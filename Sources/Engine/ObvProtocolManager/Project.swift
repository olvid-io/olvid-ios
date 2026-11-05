import ProjectDescription
import ProjectDescriptionHelpers


let name = "ObvProtocolManager"


// MARK: - Targets

private let frameworkTarget = Target.makeFrameworkTarget(
    name: name,
    dependencies: [
        .Olvid.Engine.obvCrypto,
        .Olvid.Engine.obvEncoder,
        .Olvid.Engine.obvMetaManager,
        .Olvid.Engine.obvJWS,
        .Olvid.Engine.obvOperation,
        .Olvid.Shared.obvTypes,
        .Olvid.Shared.olvidUtils,
    ])


private let frameworkTestsTarget = Target.makeFrameworkUnitTestsTarget(
    forTesting: frameworkTarget)


// MARK: - Project

let project = Project.createProjectForFramework(
    frameworkTarget: frameworkTarget,
    frameworkTestsTarget: frameworkTestsTarget)
