import ProjectDescription
import ProjectDescriptionHelpers


// MARK: - Targets

private let obvAppInboxTypes = Target.makeFrameworkTarget(
    name: "ObvAppInboxTypes",
    sourcesDirectoryName: "Types",
    dependencies: [
    ],
    enableSwift6: true)

private let obvAppInboxDatabase = Target.makeFrameworkTarget(
    name: "ObvAppInboxDatabase",
    sourcesDirectoryName: "Database",
    dependencies: [
        .target(name: "ObvAppInboxTypes"),
        .Olvid.App.obvAppTypes,
        .Olvid.App.obvAppCoreConstants,
        .Olvid.Shared.obvCoreDataStack,
        .Olvid.Shared.obvTypes,
        .Olvid.Shared.olvidUtils,
        .Olvid.Engine.obvCrypto,
    ],
    coreDataModels: [
        .olvidCoreDataModel(.appInbox),
    ],
    additionalFiles: [
        "**/*.md",
    ],
    enableSwift6: true)

private let obvAppInboxService = Target.makeFrameworkTarget(
    name: "ObvAppInboxService",
    sourcesDirectoryName: "Service",
    dependencies: [
        .target(name: "ObvAppInboxTypes"),
        .target(name: "ObvAppInboxDatabase"),
        .Olvid.Engine.obvCrypto,
        .Olvid.Shared.obvTypes,
        .Olvid.App.obvAppTypes,
    ],
    enableSwift6: true)

// MARK: - Project

let project = Project.createProjectForFrameworks(
    projectName: "ObvAppInbox",
    packages: [],
    frameworkTargets: [
        (obvAppInboxTypes, nil),
        (obvAppInboxDatabase, nil),
        (obvAppInboxService, nil),
    ])
