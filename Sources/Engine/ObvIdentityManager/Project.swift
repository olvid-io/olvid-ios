import ProjectDescription
import ProjectDescriptionHelpers


let name = "ObvIdentityManager"


// MARK: - Targets

private let frameworkTarget = Target.makeFrameworkTarget(
    name: name,
    dependencies: [
        .Olvid.Engine.obvCrypto,
        .Olvid.Engine.obvEncoder,
        .Olvid.Engine.obvMetaManager,
        .Olvid.Engine.obvJWS,
        .Olvid.Shared.obvTypes,
        .Olvid.Shared.olvidUtils,
    ])


// MARK: - Project

let project = Project.createProjectForFramework(
    frameworkTarget: frameworkTarget,
    frameworkTestsTarget: nil)
