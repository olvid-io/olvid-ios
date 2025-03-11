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

let project = Project.createProjectForApp(name: "ObvMessenger",
                                          packages: [
                                            //.remote(url: "https://github.com/olvid-io/AppAuth-iOS-for-Olvid", requirement: .branch("targetfix")),
                                            .remote(url: "https://github.com/openid/AppAuth-iOS", requirement: .exact(.init(1, 7, 5))),
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
                                          ])
