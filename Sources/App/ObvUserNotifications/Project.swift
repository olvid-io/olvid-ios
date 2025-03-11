import ProjectDescription
import ProjectDescriptionHelpers

private let obvUserNotificationsTypes = Target.makeFrameworkTarget(
    name: "ObvUserNotificationsTypes",
    sourcesDirectoryName: "Types",
    dependencies: [],
    prepareForSwift6: true)

    
private let obvUserNotificationsDatabase = Target.makeFrameworkTarget(
    name: "ObvUserNotificationsDatabase",
    sourcesDirectoryName: "Database",
    dependencies: [
        .target(name: "ObvUserNotificationsTypes"),
        .Olvid.Engine.obvCrypto,
        .Olvid.Shared.obvTypes,
        .Olvid.App.obvAppTypes,
    ],
    coreDataModels: [
        .olvidCoreDataModel(.userNotification),
    ],
    prepareForSwift6: true)


private let obvUserNotificationsSounds = Target.makeFrameworkTarget(
    name: "ObvUserNotificationsSounds",
    sourcesDirectoryName: "Sounds",
    resources: [
        "Sounds/Resources/**/*.caf",
        "Sounds/Resources/Localizable.xcstrings",
    ],
    dependencies: [
        .Olvid.App.obvAppCoreConstants,
    ],
    prepareForSwift6: true)


private let obvUserNotificationsCreator = Target.makeFrameworkTarget(
    name: "ObvUserNotificationsCreator",
    sourcesDirectoryName: "Creator",
    resources: [
        "Creator/Resources/Localizable.xcstrings",
    ],
    dependencies: [
        .sdk(name: "UserNotifications", type: .framework),
        .target(name: "ObvUserNotificationsTypes"),
        .Olvid.App.obvUICoreData,
        .Olvid.App.obvSettings,
        .Olvid.App.obvCommunicationInteractor,
        .Olvid.App.obvAppTypes,
        .Olvid.App.obvUICoreDataStructs,
        .Olvid.App.obvAppDatabase,
        .Olvid.App.obvAppCoreConstants,
        .Olvid.Shared.obvCoreDataStack,
        .Olvid.Shared.olvidUtils,
        .Olvid.Shared.obvTypes,
    ],
    prepareForSwift6: true)


let project = Project.createProjectForFrameworks(
    projectName: "ObvUserNotifications",
    packages: [],
    frameworkTargets: [
        (obvUserNotificationsTypes, nil),
        (obvUserNotificationsDatabase, nil),
        (obvUserNotificationsSounds, nil),
        (obvUserNotificationsCreator, nil),
    ])
