import ProjectDescription
import ProjectDescriptionHelpers


// We use the "Xcode's default integration" way for including the AppAuth package.
// See https://docs.tuist.io/guides/develop/projects/dependencies#external-dependencies


let shareExtensionForProduction: Target = .makeShareExtensionTarget(appType: .production)
let shareExtensionForDevelopment: Target = .makeShareExtensionTarget(appType: .development)

let notificationExtensionForProduction: Target = .makeNotificationServiceExtensionTarget(appType: .production)
let notificationExtensionForDevelopment: Target = .makeNotificationServiceExtensionTarget(appType: .development)

let intentsExtensionForProduction: Target = .makeIntentsServiceExtensionTarget(appType: .production)
let intentsExtensionForDevelopment: Target = .makeIntentsServiceExtensionTarget(appType: .development)

let externalDependencies: [TargetDependency] = [
    .package(product: "AppAuth"),
    .xcframework(path: .relativeToRoot("ExternalDependencies/XCFrameworks/WebRTC.xcframework")),
    //.sdk(name: "QuickLookUI", type: .framework, status: .optional, condition: .some(.when(.init(arrayLiteral: .catalyst))!)),
  ]

let appForProduction: Target = .makeMainAppTarget(appType: .production,
                                                  externalDependencies: externalDependencies,
                                                  shareExtension: shareExtensionForProduction,
                                                  notificationExtension: notificationExtensionForProduction,
                                                  intentsExtension: intentsExtensionForProduction)

let appForDevelopment: Target = .makeMainAppTarget(appType: .development,
                                                   externalDependencies: externalDependencies,
                                                   shareExtension: shareExtensionForDevelopment,
                                                   notificationExtension: notificationExtensionForDevelopment,
                                                   intentsExtension: intentsExtensionForDevelopment)

/// The app's own unit tests. It hosts no app — see `Target.makeAppUnitTestsTarget(name:sourcesUnderTest:dependencies:)`
/// — so every app file it exercises has to be listed here and is compiled a second time. `ObvDeepLink` only imports
/// frameworks, which is what makes that possible; a file that reached into the app target proper would not qualify.
/// The four inbox-drain files are here for the same reason and were split out of larger ones to earn it: the rule
/// deciding when the next drain window is asked for is pure logic, and it lived in `BackgroundTasksManager`, which
/// reaches half the app; the rule deciding whether a drain should run another round is pure logic too, and it lived
/// on `BootstrapCoordinator`, which reaches at least as much; and the walk through a backlog's timeline lived in
/// `InboxMaintenanceModel`, a `@MainActor` `ObservableObject` reaching SwiftUI and the engine. `ExportProgressReportFilter` is the
/// rule deciding which progress reports of a draft's video export reach the composition bar, kept out of `DraftVideoVariantsMaker`.
/// `TheRowsGivenAModelOnTheFirstFrame` is the window of rows a discussion builds before its first frame, kept out of `SingleDiscussionViewAppDataSource`.
let appTests: Target = .makeAppUnitTestsTarget(
    name: "ObvMessengerTests",
    sourcesUnderTest: [
        .glob("App/Sources/Utils/ObvDeepLink.swift"),
        .glob("App/Sources/Coordinators/BoostrapCoordinator/EngineInboxDrain/ObvInboxDrainStopReason.swift"),
        .glob("App/Sources/Coordinators/BoostrapCoordinator/EngineInboxDrain/ObvInboxDrainWindowSchedule.swift"),
        .glob("App/Sources/Coordinators/BoostrapCoordinator/EngineInboxDrain/ObvInboxDrainRoundDecision.swift"),
        .glob("App/Sources/Coordinators/BoostrapCoordinator/EngineInboxDrain/ObvInboxDrainBacklogWalk.swift"),
        .glob("App/Sources/Coordinators/PersistedDiscussionsUpdatesCoordinator/ExportProgressReportFilter.swift"),
        .glob("App/Sources/DataSources/ObvSingleDiscussion/TheRowsGivenAModelOnTheFirstFrame.swift"),
    ],
    dependencies: [
        .Olvid.Shared.obvTypes,
        .Olvid.Shared.olvidUtils,
        .Olvid.Engine.obvEngine,
        .Olvid.App.obvAppTypes,
        .Olvid.App.obvUICoreData,
    ])

private let swiftUIIntrospectURL: String = "https://github.com/siteline/swiftui-introspect"
                                                

let project = Project.createProjectForApp(name: "ObvMessenger",
                                          packages: [
                                            .remote(url: "https://github.com/openid/AppAuth-iOS", requirement: .exact(.init(2, 0, 0))),
                                            //.remote(url: swiftUIIntrospectURL, requirement: .exact(.init(26, 0, 1))),
                                            .remote(url: swiftUIIntrospectURL, requirement: .exact(.init(27, 0, 0, prereleaseIdentifiers: ["beta", "3"])))
                                          ],
                                          targets: [
                                            shareExtensionForProduction,
                                            shareExtensionForDevelopment,
                                            notificationExtensionForProduction,
                                            notificationExtensionForDevelopment,
                                            intentsExtensionForProduction,
                                            intentsExtensionForDevelopment,
                                            appForProduction,
                                            appForDevelopment,
                                            appTests,
                                          ])
