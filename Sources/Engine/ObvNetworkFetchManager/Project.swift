import ProjectDescription
import ProjectDescriptionHelpers


let name = "ObvNetworkFetchManager"


// MARK: - Targets

private let frameworkTarget = Target.makeFrameworkTarget(
    name: name,
    dependencies: [
        .Olvid.Engine.obvCrypto,
        .Olvid.Engine.obvEncoder,
        .Olvid.Engine.obvMetaManager,
        .Olvid.Engine.obvOperation,
        .Olvid.Engine.obvServerInterface,
        .Olvid.Shared.obvTypes,
        .Olvid.Shared.olvidUtils,
    ])


// MARK: - Project

let project = Project.createProjectForFramework(
    frameworkTarget: frameworkTarget,
    frameworkTestsTarget: nil)
