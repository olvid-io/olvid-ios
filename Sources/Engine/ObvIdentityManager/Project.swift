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


private let frameworkTestsTarget = Target.makeFrameworkUnitTestsTarget(
    forTesting: frameworkTarget,
    dependencies: [
        .Olvid.Engine.obvDatabaseManager, // The engine's Core Data model, for tests that need a store
    ])


// MARK: - Project

let project = Project.createProjectForFramework(
    frameworkTarget: frameworkTarget,
    frameworkTestsTarget: frameworkTestsTarget)
