import ProjectDescription
import ProjectDescriptionHelpers


let name = "ObvDatabaseManager"


// MARK: - Targets

private let frameworkTarget = Target.makeFrameworkTarget(
    name: name,
    resources: [
        "**/*.xcmappingmodel",
    ],
    dependencies: [
        .Olvid.Engine.obvCrypto,
        .Olvid.Engine.obvEncoder,
        .Olvid.Engine.obvMetaManager,
        .Olvid.Shared.obvTypes,
        .Olvid.Shared.olvidUtils,
        .Olvid.Shared.obvCoreDataStack,
    ],
    coreDataModels: [.olvidCoreDataModel(.engine)],
    additionalFiles: [
        "**/*.md",
        "**/*.rtf",
        "**/*.txt",
    ])


// MARK: - Project

let project = Project.createProjectForFramework(
    frameworkTarget: frameworkTarget,
    frameworkTestsTarget: nil)
