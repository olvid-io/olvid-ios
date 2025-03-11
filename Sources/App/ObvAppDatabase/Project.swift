import ProjectDescription
import ProjectDescriptionHelpers


let name = "ObvAppDatabase"


// MARK: - Targets

private let frameworkTarget = Target.makeFrameworkTarget(
    name: name,
    resources: [
        "**/*.xcmappingmodel",
    ],
    dependencies: [
        .Olvid.Shared.obvCoreDataStack,
        .Olvid.Shared.obvTypes,
        .Olvid.Engine.obvCrypto,
        .Olvid.App.obvSystemIcon,
        .Olvid.App.obvSettings,
    ],
    coreDataModels: [.olvidCoreDataModel(.app)],
    additionalFiles: [
        "Sources/**/*.md",
    ],
    prepareForSwift6: true)



// MARK: - Project

let project = Project.createProjectForFramework(
    frameworkTarget: frameworkTarget,
    frameworkTestsTarget: nil)
