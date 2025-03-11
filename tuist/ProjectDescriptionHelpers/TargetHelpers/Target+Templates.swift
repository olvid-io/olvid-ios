import ProjectDescription

// MARK: - For Frameworks

extension Target {
    
    /// See ``https://developer.apple.com/documentation/Xcode/configuring-your-project-to-use-mergeable-libraries`` for an understanding of `mergedBinaryType` and `mergeable`.
    public static func makeFrameworkTarget(name: String,
                                           infoPlist: InfoPlist = .default,
                                           sourcesDirectoryName: String = "",
                                           resources: ProjectDescription.ResourceFileElements? = nil,
                                           dependencies: [TargetDependency],
                                           coreDataModels: [CoreDataModel] = [],
                                           additionalFiles: [ProjectDescription.FileElement] = [],
                                           prepareForSwift6: Bool = false,
                                           enableSwift6: Bool = false) -> Target {
        
        let settings: Settings = .settingsForFrameworkTarget(prepareForSwift6: prepareForSwift6, enableSwift6: enableSwift6)
        
        let sources = sourcesDirectoryName.isEmpty ? "Sources/**/*.swift" : [sourcesDirectoryName, "Sources/**/*.swift"].joined(separator: "/")
        
        return .target(name: name,
                       destinations: Constant.destinations,
                       product: .framework,
                       productName: nil,
                       bundleId: "io.olvid.\(name)",
                       deploymentTargets: Constant.deploymentTargets,
                       infoPlist: infoPlist,
                       sources: [.init(stringLiteral: sources)],
                       resources: resources,
                       copyFiles: nil,
                       headers: nil,
                       entitlements: nil,
                       scripts: [],
                       dependencies: dependencies,
                       settings: settings,
                       coreDataModels: coreDataModels,
                       environmentVariables: [:],
                       launchArguments: [],
                       additionalFiles: additionalFiles,
                       buildRules: [],
                       mergedBinaryType: .disabled,
                       mergeable: false,
                       onDemandResourcesTags: nil)
        
    }
    
    
    public static func makeFrameworkUnitTestsTarget(forTesting testedTarget: Target,
                                                    resources: ProjectDescription.ResourceFileElements? = nil) -> Target {
        .target(name: "\(testedTarget.name)Tests",
                destinations: Constant.destinations,
                product: .unitTests,
                productName: nil,
                bundleId: "\(testedTarget.bundleId).tests",
                deploymentTargets: Constant.deploymentTargets,
                infoPlist: .default,
                sources: ["Tests/**/*.swift"],
                resources: resources,
                copyFiles: nil,
                headers: nil,
                entitlements: nil,
                scripts: [],
                dependencies: [.target(name: testedTarget.name)],
                settings: .settings(
                    base: ["DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER": .init(booleanLiteral: false)],
                    configurations: [],
                    defaultSettings: .recommended),
                coreDataModels: [],
                environmentVariables: [:],
                launchArguments: [],
                additionalFiles: [],
                buildRules: [],
                mergedBinaryType: .disabled,
                mergeable: false,
                onDemandResourcesTags: nil)
    }

}


// MARK: - For App Extensions

extension Target {
    
    public static func makeIntentsServiceExtensionTarget(appType: OlvidAppType) -> Self {
        
        let name = Constant.olvidTargetNames(for: appType).intentsExtension

        let bundleId = Constant.olvidBundleIdentifiers(for: appType).intentsExtension
        
        let infoPlist: InfoPlist = .forOlvidIntentsServiceExtension(appType: appType)

        let sources: SourceFilesList = [
            "Extensions/IntentsExtension/Sources/**/*.swift",
        ]
        
        let entitlements: Entitlements = .forIntentsServiceExtension()
        
        let dependencies: [TargetDependency] = [
            .sdk(name: "Intents", type: .framework, status: .required)
        ]
        
        let settings: Settings = .settingsOfAppExtensionTarget()

        let target = Target.makeAppExtensionTarget(name: name,
                                                   bundleId: bundleId,
                                                   infoPlist: infoPlist,
                                                   sources: sources,
                                                   resources: [],
                                                   entitlements: entitlements,
                                                   dependencies: dependencies,
                                                   settings: settings)
        
        return target
        
    }
    
    public static func makeNotificationServiceExtensionTarget(appType: OlvidAppType) -> Self {
        
        let name = Constant.olvidTargetNames(for: appType).notificationExtension

        let bundleId = Constant.olvidBundleIdentifiers(for: appType).notificationExtension
        
        let infoPlist: InfoPlist = .forOlvidNotificationServiceExtension(appType: appType)
        
        // There is way too much source files here. Eventually, we should create subprojects to share code between the App and the Notification extension
        // and reduce the number of dependencies.
        let sources: SourceFilesList = [
            "Extensions/NotificationServiceExtension/Sources/**/*.swift",
            "App/Sources/Singletons/ObvStack.swift",
        ]
        
        let resources: ResourceFileElements = [
            "Extensions/NotificationServiceExtension/Resources/PrivacyInfo.xcprivacy",
            "App/Resources/Localizable.xcstrings",
            "App/Resources/*.xcassets",
        ]
        
        let entitlements: Entitlements = .forNotificationServiceExtension(appType: appType)
        
        let dependencies: [TargetDependency] = [
            .sdk(name: "UserNotifications", type: .framework),
            .sdk(name: "UIKit", type: .framework),
            .package(product: "AppAuth"), // See the .remote package declaration when creating the project
            .Olvid.App.obvAppCoreConstants,
            .Olvid.App.obvUICoreData,
            .Olvid.App.obvSettings,
            .Olvid.App.obvCommunicationInteractor,
            .Olvid.App.obvUI,
            .Olvid.App.ObvUserNotifications.database,
            .Olvid.App.ObvUserNotifications.sounds,
            .Olvid.App.ObvUserNotifications.creator,
            .Olvid.App.UI.obvImageEditor,
            .Olvid.Engine.obvEngine,
            .Olvid.Engine.obvCrypto,
            .Olvid.Shared.olvidUtils,
            .Olvid.Shared.obvTypes,
        ]
        
        let settings: Settings = .settingsOfAppExtensionTarget()
        
        let target = Target.makeAppExtensionTarget(name: name,
                                                   bundleId: bundleId,
                                                   infoPlist: infoPlist,
                                                   sources: sources,
                                                   resources: resources,
                                                   entitlements: entitlements,
                                                   dependencies: dependencies,
                                                   settings: settings)

        return target

    }
    
    
    public static func makeShareExtensionTarget(appType: OlvidAppType) -> Self {
        
        let name = Constant.olvidTargetNames(for: appType).shareExtension
        
        let bundleId = Constant.olvidBundleIdentifiers(for: appType).shareExtension
        
        let infoPlist: InfoPlist = .forOlvidShareExtension(appType: appType)
        
        // This will need to be organized and not have target files from other targets
        let sources: SourceFilesList = [
            "Extensions/ShareExtension/Sources/**/*.swift",
            "App/Sources/Constants/ObvMessengerConstants.swift",
            "App/Sources/Coordinators/ContactGroupCoordinator/Operations/CreateOrUpdatePersistedGroupV2Operation.swift",
            "App/Sources/Coordinators/ContactGroupCoordinator/Operations/DeletePersistedGroupV2Operation.swift",
            "App/Sources/Coordinators/ContactGroupCoordinator/Operations/MarkPublishedDetailsOfGroupV2AsSeenOperation.swift",
            "App/Sources/Coordinators/ContactGroupCoordinator/Operations/RemoveUpdateInProgressForGroupV2Operation.swift",
            "App/Sources/Coordinators/ContactGroupCoordinator/Operations/UpdateGroupV2Operation.swift",
            "App/Sources/Coordinators/PersistedDiscussionsUpdatesCoordinator/Operations/Deleting messages and discussions/WipeAllReadOnceAndLimitedVisibilityMessagesAfterLockOutOperation.swift",
            "App/Sources/Coordinators/PersistedDiscussionsUpdatesCoordinator/Protocols/OperationProvidingLoadedItemProvider.swift",
            "App/Sources/CoreData/DataMigrationManagerForObvMessenger.swift",
            "App/Sources/CoreData/ObvMessengerPersistentContainer.swift",
            "App/Sources/Invitation Flow/SubViews/CircleAndTitlesView.swift",
            "App/Sources/Invitation Flow/SubViews/CircledCameraButtonView.swift",
            "App/Sources/Invitation Flow/SubViews/CircledSymbolView.swift",
            "App/Sources/Invitation Flow/SubViews/IdentityCardContentView.swift",
            "App/Sources/Invitation Flow/SubViews/OlvidButton.swift",
            "App/Sources/Invitation Flow/SubViews/ProfilePictureView.swift",
            "App/Sources/Invitation Flow/SubViews/TextView.swift",
            "App/Sources/LocalAuthentication/LocalAuthenticationViewController.swift",
            "App/Sources/LocalAuthentication/LocalAuthenticationViewControllerDelegate.swift",
            "App/Sources/Localization/CommonString.swift",
            "App/Sources/Main/Settings/AllSettings/Privacy/VerifyPasscodeViewController.swift",
            "App/Sources/Managers/HardLinksToFylesManager/HardLinksToFylesManager.swift",
            "App/Sources/Managers/IntentManager/IntentManagerUtils.swift",
            "App/Sources/Managers/KeycloakManager/KeycloakServerRevocationsAndStuff.swift",
            "App/Sources/Managers/KeycloakManager/KeycloakUserDetailsAndStuff.swift",
            "App/Sources/Managers/LocalAuthenticationManager/LocalAuthenticationManager.swift",
            "App/Sources/Managers/SnackBarManager/OlvidSnackBarCategory.swift",
            "App/Sources/Managers/ThumbnailManager/ThumbnailManager.swift",
            "App/Sources/Managers/UserNotificationManager/Note.swift",
            "App/Sources/Notifications/HardLinksToFylesNotifications.swift",
            "App/Sources/Notifications/ObvMessengerGroupV2Notifications.swift",
            "App/Sources/Notifications/ObvMessengerInternalNotification.swift",
            "App/Sources/ObvMessengerShareExtension/Operations/FetchAndCacheObvLinkMetadataForFirstURLInLoadedItemProvidersOperation.swift",
            "App/Sources/Onboarding/BackupRestore/ObvImageButton.swift",
            "App/Sources/OwnedIdentityChooser/LatestCurrentOwnedIdentityStorage.swift",
            "App/Sources/OwnedIdentityChooser/OwnedIdentityChooserViewController.swift",
            "App/Sources/Singletons/AppTheme.swift",
            "App/Sources/Singletons/ObvStack.swift",
            "App/Sources/Singletons/ObvUserActivitySingleton/OlvidUserActivity.swift",
            "App/Sources/TableViewControllers/Contacts/MultiContactChooserViewController/FloatingActionButton.swift",
            "App/Sources/Types/ObvLinkMetadata+LPLinkMetadata.swift",
            "App/Sources/Types/ObvLinkMetadata.swift",
            "App/Sources/Types/OlvidURL.swift",
            "App/Sources/Types/OlvidUserId.swift",
            "App/Sources/UIElements/HUD/SwiftUI/ObvActivityIndicatorView.swift",
            "App/Sources/UIElements/HUD/UIKit/HUDs/ObvHUDView.swift",
            "App/Sources/UIElements/HUD/UIKit/HUDs/ObvIconHUD.swift",
            "App/Sources/UIElements/HUD/UIKit/HUDs/ObvLoadingHUD.swift",
            "App/Sources/UIElements/HUD/UIKit/HUDs/ObvTextHUD.swift",
            "App/Sources/UIElements/HUD/UIKit/ObvCanShowHUD.swift",
            "App/Sources/UIElements/HUD/UIKit/ObvHUDType.swift",
            "App/Sources/UIElements/HUD/UIKit/UIViewController+ObvCanShowHUD.swift",
            "App/Sources/UIElements/ImageEditor.swift",
            "App/Sources/UIElements/ImagePicker.swift",
            "App/Sources/UIElements/InitialCircleView.swift",
            "App/Sources/UIElements/ObvCardView.swift",
            "App/Sources/UIElements/PasscodeUtils.swift",
            "App/Sources/UIElements/StandardViewControllerSubclasses/ObvNavigationController.swift",
            "App/Sources/UIElements/SwiftUIUtils.swift",
            "App/Sources/UIElements/UIButtonViewController.swift",
            "App/Sources/Utils/Atomic.swift",
            "App/Sources/Utils/BlockBarButtonItem.swift",
            "App/Sources/Utils/Concurrency.swift",
            "App/Sources/Utils/Loading Item Providers/LoadItemProviderOperation.swift",
            "App/Sources/Utils/ObvDeepLink.swift",
            "App/Sources/Utils/SoundsPlayer.swift",
            "App/Sources/Utils/TimeUtils.swift",
            "App/Sources/Utils/UIImage+Utils.swift",
            "App/Sources/Utils/UIView+AppTheme.swift",
            "App/Sources/Utils/UIView+EdgeConstraints.swift",
            "App/Sources/Utils/UIViewController+ContentController.swift",
            "App/Sources/Utils/URL+MoveToTrash.swift",
            "App/Sources/Utils/URL+Thumbnail.swift",
            "App/Sources/VoIP/Helpers/CallSounds.swift",
        ]
      
        let resources: ResourceFileElements = [
            "Extensions/ShareExtension/Resources/**/*",
            "App/Resources/LaunchScreen.storyboard",
            "App/Resources/*.xcassets",
        ]

        let entitlements: Entitlements = .forShareExtension(appType: appType)
      
        let dependencies: [TargetDependency] = [
            .sdk(name: "UIKit", type: .framework),
            .Olvid.Shared.obvTypes,
            .Olvid.Shared.olvidUtils,
            .Olvid.Shared.obvCoreDataStack,
            .Olvid.App.obvAppCoreConstants,
            .Olvid.App.obvDesignSystem,
            .Olvid.App.obvSettings,
            .Olvid.App.obvUI,
            .Olvid.App.obvUICoreData,
            .Olvid.App.obvSystemIcon,
            .Olvid.App.obvAppTypes,
            .Olvid.App.obvKeycloakManager,
            .Olvid.App.UI.obvCircledInitials,
            .Olvid.Engine.obvCrypto,
            .Olvid.Engine.obvEngine,
            .Olvid.App.UI.obvImageEditor,
         ]

        let settings: Settings = .settingsOfAppExtensionTarget()
        
        let target = Target.makeAppExtensionTarget(name: name,
                                                   bundleId: bundleId,
                                                   infoPlist: infoPlist,
                                                   sources: sources,
                                                   resources: resources,
                                                   entitlements: entitlements,
                                                   dependencies: dependencies,
                                                   settings: settings)
        
        return target
        
    }
    
    
    /// Used when creating an app extension target (i.e., either the share, notification, or intents extension)
    private static func makeAppExtensionTarget(name: String,
                                              bundleId: String,
                                              infoPlist: InfoPlist,
                                              sources: SourceFilesList?,
                                              resources: ResourceFileElements?,
                                              entitlements: Entitlements?,
                                              dependencies: [TargetDependency],
                                              settings: Settings?) -> Target {
        
        return .target(name: name,
                       destinations: Constant.destinations,
                       product: .appExtension,
                       productName: name,
                       bundleId: bundleId,
                       deploymentTargets: Constant.deploymentTargets,
                       infoPlist: infoPlist,
                       sources: sources,
                       resources: resources,
                       copyFiles: nil,
                       headers: nil,
                       entitlements: entitlements,
                       scripts: [],
                       dependencies: dependencies,
                       settings: settings,
                       coreDataModels: [],
                       environmentVariables: [:],
                       launchArguments: [],
                       additionalFiles: [],
                       buildRules: [],
                       mergedBinaryType: .disabled,
                       mergeable: false,
                       onDemandResourcesTags: nil)
        
    }

}


// MARK: - For the main App

extension Target {
    
    public static func makeMainAppTarget(appType: OlvidAppType,
                                         externalDependencies: [TargetDependency],
                                         shareExtension: Target,
                                         notificationExtension: Target,
                                         intentsExtension: Target) -> Self {
        
        let name = Constant.olvidTargetNames(for: appType).app
        
        let bundleId = Constant.olvidBundleIdentifiers(for: appType).app

        let infoPlist: InfoPlist = .forOlvidMainAppTarget(for: appType)
        
        let sources: SourceFilesList = [
            "App/Sources/**/*.swift",
            "App/Sources/**/*.xcmappingmodel",
        ]
        
        let resources: ResourceFileElements = [
            "App/Resources/*.xcassets",
            "App/Resources/**/*.xcstrings",
            "App/Resources/**/*.lproj/AppIntentVocabulary.plist",
            "App/Resources/LaunchScreen.storyboard",
            "App/Resources/PrivacyInfo.xcprivacy",
            "App/Resources/Settings.bundle",
            "App/Resources/CallSounds/*.mp3",
            "App/Sources/**/*.xib",
        ]
        
        let internalDependencies: [TargetDependency] = [
            .target(shareExtension),
            .target(notificationExtension),
            .target(intentsExtension),
            .Olvid.App.obvAppCoreConstants,
            .Olvid.App.obvUICoreData,
            .Olvid.App.obvDesignSystem,
            .Olvid.App.Discussions.Mentions.AutoGrowingTextView.textViewDelegateProxy,
            .Olvid.App.Discussions.Mentions.Builders.composeMessage,
            .Olvid.App.Discussions.Mentions.Builders.buildersShared,
            .Olvid.App.Discussions.scrollToBottomButton,
            .Olvid.App.obvSettings,
            .Olvid.App.ObvUserNotifications.sounds,
            .Olvid.App.Platform.uiKitAdditions,
            .Olvid.App.Platform.base,
            .Olvid.App.Components.textInputShortcutsResultView,
            .Olvid.App.Components.obvEmojiUtils,
            .Olvid.App.UI.obvPhotoButton,
            .Olvid.App.UI.obvCircledInitials,
            .Olvid.App.UI.obvImageEditor,
            .Olvid.App.UI.obvScannerHostingView,
            .Olvid.App.obvSystemIcon,
            .Olvid.App.obvUI,
            .Olvid.App.obvLocation,
            .Olvid.App.obvAppTypes,
            .Olvid.App.obvKeycloakManager,
            .Olvid.App.obvOnboarding,
            .Olvid.App.obvSubscription,
            .Olvid.Engine.obvEngine,
            .Olvid.Engine.obvCrypto,
            .Olvid.Engine.obvEncoder,
            .Olvid.Engine.obvFlowManager,
            .Olvid.Engine.obvJWS,
            .Olvid.Shared.obvCoreDataStack,
            .Olvid.Shared.obvTypes,
            .Olvid.Shared.olvidUtils,
            .Olvid.Shared.obvNetworkStatus,
        ]
        
        let dependencies = internalDependencies + externalDependencies
        
        let entitlements: Entitlements = .forMainApp(appType: appType)
        
        let settings: Settings = .settingsOfMainAppTarget(appType: appType)
        
        let additionalFiles: [FileElement] = [
            "App/TestConfiguration.storekit",
            "App/SyncedConfiguration.storekit",
        ]
        
        let target: Target = .target(name: name,
                                     destinations: Constant.destinations,
                                     product: .app,
                                     productName: name,
                                     bundleId: bundleId,
                                     deploymentTargets: Constant.deploymentTargets,
                                     infoPlist: infoPlist,
                                     sources: sources,
                                     resources: resources,
                                     copyFiles: nil,
                                     headers: nil,
                                     entitlements: entitlements,
                                     scripts: [],
                                     dependencies: dependencies,
                                     settings: settings,
                                     coreDataModels: [],
                                     environmentVariables: [:],
                                     launchArguments: [],
                                     additionalFiles: additionalFiles,
                                     buildRules: [],
                                     mergedBinaryType: .disabled,
                                     mergeable: false,
                                     onDemandResourcesTags: nil)

        return target
        
    }
        
}


// MARK: - For ObjectiveC libraries

extension Target {
    
    public static func makeObjectiveCLibraryTarget(name: String,
                                                   sources: SourceFilesList,
                                                   headers: Headers?,
                                                   dependencies: [TargetDependency],
                                                   isExtensionSafe: Bool) -> Target {
        
        let settings: Settings = .settingsOfObjectiveCLibraryTarget()

        return .target(name: name,
                       destinations: Constant.destinations,
                       product: .framework,
                       productName: name,
                       bundleId: bundleIdentifier(for: name),
                       deploymentTargets: Constant.deploymentTargets,
                       infoPlist: .default,
                       sources: sources,
                       resources: nil,
                       copyFiles: nil,
                       headers: headers,
                       entitlements: nil,
                       scripts: [],
                       dependencies: dependencies,
                       settings: settings,
                       coreDataModels: [],
                       environmentVariables: [:],
                       launchArguments: [],
                       additionalFiles: [],
                       buildRules: [],
                       mergedBinaryType: .disabled,
                       mergeable: false,
                       onDemandResourcesTags: nil)
        
    }
    
}


// MARK: - For Swift libraries

extension Target {
    
    public static func makeSwiftLibraryTarget(name: String,
                                              sources: SourceFilesList,
                                              resources: ProjectDescription.ResourceFileElements?,
                                              dependencies: [TargetDependency],
                                              isExtensionSafe: Bool) -> Target {
        
        let settings: Settings = .settingsOfSwiftLibraryTarget()

        return .target(name: name,
                       destinations: Constant.destinations,
                       product: .framework,
                       productName: nil,
                       bundleId: bundleIdentifier(for: name),
                       deploymentTargets: Constant.deploymentTargets,
                       infoPlist: .default,
                       sources: sources,
                       resources: resources,
                       copyFiles: nil,
                       headers: nil,
                       entitlements: nil,
                       scripts: [],
                       dependencies: dependencies,
                       settings: settings,
                       coreDataModels: [],
                       environmentVariables: [:],
                       launchArguments: [],
                       additionalFiles: [],
                       buildRules: [],
                       mergedBinaryType: .disabled,
                       mergeable: false,
                       onDemandResourcesTags: nil)
        
    }
    
    
}


// MARK: - Private helpers

private func bundleIdentifier(for name: String) -> String {
    let name = name.replacingOccurrences(of: "_", with: "-")
    return "io.olvid.\(name)"
}
