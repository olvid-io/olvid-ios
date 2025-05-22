import ProjectDescription
import ProjectDescriptionHelpers

let name = "ObvBackupManagerNew"


// MARK: - Targets

private let frameworkTarget = Target.makeFrameworkTarget(
    name: name,
    dependencies: [
        .Olvid.Engine.obvCrypto,
        .Olvid.Engine.obvServerInterface,
        .Olvid.Engine.obvEncoder,
        .Olvid.Engine.obvMetaManager,
        .Olvid.Shared.olvidUtils,
        .Olvid.Shared.obvCoreDataStack,
        .Olvid.Shared.obvTypes,
    ],
    coreDataModels: [.olvidCoreDataModel(.backup)]
)

// MARK: - Project

let project = Project.createProjectForFramework(
    frameworkTarget: frameworkTarget,
    frameworkTestsTarget: nil)
