import ProjectDescription


extension InfoPlist {
    
    public static func forOlvidMainAppTarget(for appType: OlvidAppType) -> Self {
        
        let cfBundleDocumentTypes: Plist.Value = .array([
            .dictionary([
                "CFBundleTypeName": .string("com.adobe.pdf"),
                "CFBundleTypeRole": .string("None"),
                "LSHandlerRank": .string("Default"),
                "LSItemContentTypes": .array([.string("com.adobe.pdf")]),
            ]),
            .dictionary([
                "CFBundleTypeName": .string("Olvid Backup"),
                "LSHandlerRank": .string("Owner"),
                "LSItemContentTypes": .array([.string("io.olvid.type.olvidbackup")]),
            ]),
            .dictionary([
                "CFBundleTypeName": .string("Olvid Link Preview"),
                "LSHandlerRank": .string("Owner"),
                "LSItemContentTypes": .array([.string("olvid.link-preview")]),
            ]),
            .dictionary([
                "CFBundleTypeName": .string("public.comma-separated-values-text"),
                "LSHandlerRank": .string("Default"),
                "LSItemContentTypes": .array([.string("public.comma-separated-values-text")]),
            ]),
            .dictionary([
                "CFBundleTypeName": .string("Microsoft Word 97 document"),
                "LSHandlerRank": .string("Default"),
                "LSItemContentTypes": .array([.string("com.microsoft.word.doc")]),
            ]),
            .dictionary([
                "CFBundleTypeName": .string("Apple m4a Audio"),
                "LSHandlerRank": .string("Default"),
                "LSItemContentTypes": .array([.string("com.apple.m4a-audio")]),
            ]),
            .dictionary([
                "CFBundleTypeName": .string("Microsoft Word document"),
                "LSHandlerRank": .string("Default"),
                "LSItemContentTypes": .array([.string("org.openxmlformats.wordprocessingml.document")]),
            ]),
            .dictionary([
                "CFBundleTypeName": .string("Microsoft Powerpoint document"),
                "LSHandlerRank": .string("Default"),
                "LSItemContentTypes": .array([.string("org.openxmlformats.presentationml.presentation")]),
            ]),
            .dictionary([
                "CFBundleTypeName": .string("Microsoft Excel document"),
                "LSHandlerRank": .string("Default"),
                "LSItemContentTypes": .array([.string("org.openxmlformats.spreadsheetml.sheet")]),
            ]),
        ])
        
        let cfBundleURLTypes: Plist.Value = .array([
            .dictionary([
                "CFBundleTypeRole": .string("Editor"),
                "CFBundleURLSchemes": .array([.string(Constant.cfBundleURLSchemes(for: appType))])
            ])
        ])
        
        let nsUserActivityTypes: Plist.Value = .array([
            .string("INSendMessageIntent"),
            .string("io.olvid.messenger.continueDiscussion"),
            .string("io.olvid.messenger.displayLatestDiscussions"),
            .string("io.olvid.messenger.displayContacts"),
            .string("io.olvid.messenger.displayGroups"),
            .string("io.olvid.messenger.displayInvitations"),
        ])
        
        let uiApplicationSceneManifest: Plist.Value = .dictionary([
            "UIApplicationSupportsMultipleScenes": .boolean(false),
            "UISceneConfigurations": .dictionary([
                "UIWindowSceneSessionRoleApplication": .array([
                    .dictionary([
                        "UISceneConfigurationName": .string("Default configuration"),
                        "UISceneDelegateClassName": .string("$(PRODUCT_MODULE_NAME).SceneDelegate"),
                    ])
                ]),
            ]),
        ])
        
        let uiBackgroundModes: Plist.Value = .array([
            .string("audio"),
            .string("remote-notification"),
            .string("voip"),
            .string("location"),
            .string("fetch"), // For app refresh background task (1 max)
            .string("processing"), // For processing background tasks (10 max)
        ])
        
        let uiSupportedInterfaceOrientations: Plist.Value = .array([
            .string("UIInterfaceOrientationPortrait"),
            .string("UIInterfaceOrientationPortraitUpsideDown"),
            .string("UIInterfaceOrientationLandscapeLeft"),
            .string("UIInterfaceOrientationLandscapeRight"),
        ])
        
        let utExportedTypeDeclarations: Plist.Value = .array([
            .dictionary([
                "UTTypeConformsTo": .array([
                    .string("public.data"),
                    .string("public.content"),
                ]),
                "UTTypeDescription": .string("Olvid Backup"),
                "UTTypeIconFiles": .array([]),
                "UTTypeIdentifier": .string("io.olvid.type.olvidbackup"),
                "UTTypeTagSpecification": .dictionary([
                    "public.filename-extension": .array([
                        .string("olvidbackup")
                    ]),
                ]),
            ]),
            .dictionary([
                "UTTypeConformsTo": .array([
                    .string("public.data"),
                    .string("public.content"),
                ]),
                "UTTypeDescription": .string("Olvid Link Preview"),
                "UTTypeIconFiles": .array([]),
                "UTTypeIdentifier": .string("olvid.link-preview"),
                "UTTypeTagSpecification": .dictionary([
                    "public.filename-extension": .array([
                        .string("olvidlinkpreview")
                    ]),
                    "public.mime-type": .array([
                        .string("olvid/link-preview")
                    ]),
                ]),
            ]),
        ])
        
        let nsAppTransportSecurity: Plist.Value = .dictionary([
            "NSAllowsArbitraryLoads": .boolean(false),
        ])
        
        let utImportedTypeDeclarations: Plist.Value = .array([
            .dictionary([
                "UTTypeDescription": .string("Web Internet Location"),
                "UTTypeIdentifier": .string("com.apple.web-internet-location"),
                "UTTypeConformsTo": .array([
                    .string("public.data"),
                ]),
            ]),
            .dictionary([
                "UTTypeDescription": .string("Apple m4a Audio"),
                "UTTypeIdentifier": .string("com.apple.m4a-audio"),
                "UTTypeConformsTo": .array([
                    .string("public.data"),
                ]),
            ]),
            .dictionary([
                "UTTypeDescription": .string("Microsoft Word 97 document"),
                "UTTypeIdentifier": .string("com.microsoft.word.doc"),
                "UTTypeConformsTo": .array([
                    .string("public.data"),
                ]),
                "UTTypeTagSpecification": .dictionary([
                    "public.filename-extension": .array([
                        .string("doc"),
                    ]),
                ]),
            ]),
            .dictionary([
                "UTTypeDescription": .string("Microsoft Word document"),
                "UTTypeIdentifier": .string("org.openxmlformats.wordprocessingml.document"),
                "UTTypeConformsTo": .array([
                    .string("public.data"),
                ]),
                "UTTypeTagSpecification": .dictionary([
                    "public.filename-extension": .array([
                        .string("docx"),
                    ]),
                ]),
            ]),
            .dictionary([
                "UTTypeDescription": .string("Microsoft Powerpoint document"),
                "UTTypeIdentifier": .string("org.openxmlformats.presentationml.presentation"),
                "UTTypeConformsTo": .array([
                    .string("public.data"),
                ]),
                "UTTypeTagSpecification": .dictionary([
                    "public.filename-extension": .array([
                        .string("pptx"),
                    ]),
                ]),
            ]),
            .dictionary([
                "UTTypeDescription": .string("Microsoft Excel document"),
                "UTTypeIdentifier": .string("org.openxmlformats.spreadsheetml.sheet"),
                "UTTypeConformsTo": .array([
                    .string("public.data"),
                ]),
                "UTTypeTagSpecification": .dictionary([
                    "public.filename-extension": .array([
                        .string("xlsx"),
                    ]),
                ]),
            ]),
            .dictionary([
                "UTTypeDescription": .string("Chromium initiated drag"),
                "UTTypeIdentifier": .string("org.chromium.chromium-initiated-drag"),
                "UTTypeConformsTo": .array([
                    .string("public.data"),
                ]),
            ]),
        ])
        
        let bgTaskSchedulerPermittedIdentifiers: ProjectDescription.Plist.Value = .array([
            .string("io.olvid.background.tasks"), // The app refresh background task (there can be only one)
            .string("io.olvid.background.processing.database.sync"), // A processing background task for syncing the app database with the engine database (there can be at most 10 processing tasks)
            .string("io.olvid.background.processing.perform.new.backup"), // A processing background task for performing a (new) backup of all the profiles
        ])
        
        let standardPlistValuesForExtendingDefault: [String : ProjectDescription.Plist.Value] = [
            "CFBundleShortVersionString": .string(Version.marketingVersion),
            "CFBundleVersion": .string(Version.currentProjectVersion),
            "BGTaskSchedulerPermittedIdentifiers": bgTaskSchedulerPermittedIdentifiers,
            "CFBundleDocumentTypes": cfBundleDocumentTypes,
            "CFBundleURLTypes": cfBundleURLTypes,
            "CFBundleDisplayName": .string(Constant.olvidBundleDisplayName(for: appType)),
            "NSHumanReadableCopyright": .string(Constant.nsHumanReadableCopyrightValue),
            "ITSAppUsesNonExemptEncryption": .boolean(false),
            "LSApplicationCategoryType": .string(Constant.appCategory),
            "LSRequiresIPhoneOS": .boolean(true),
            "LSSupportsOpeningDocumentsInPlace": .boolean(true),
            "NSCameraUsageDescription": .string("Access to the camera allows you to scan the QR code of your contacts and to take pictures and videos right from within a discussion."),
            "NSFaceIDUsageDescription": .string("Use Face ID to access Olvid"),
            "NSMicrophoneUsageDescription": .string("Allowing access to the microphone is required to make secure audio calls and to record movies and voice messages."),
            "NSPhotoLibraryAddUsageDescription": .string("Write access is required to save a picture to your photo library. Please note that Olvid will not have access to the other photos of your photo library."),
            "NSLocationWhenInUseUsageDescription": .string("Your location is necessary when you decide to share it with other users."),
            "NSLocationUsageDescription": .string("Your location is necessary when you decide to share it with other users."), // 2025-01-13: although this key is deprecated, the App Store Review complained it is missing for macOS
            "NSLocationAlwaysAndWhenInUseUsageDescription": .string("Your location is necessary when you decide to share it with other users."),
            "NSLocationAlwaysUsageDescription": .string("Your location is necessary when you decide to share it with other users."),
            "NSUserActivityTypes": nsUserActivityTypes,
            "UIApplicationSceneManifest": uiApplicationSceneManifest,
            "UIBackgroundModes": uiBackgroundModes,
            "UIFileSharingEnabled": .boolean(true),
            "UILaunchStoryboardName": .string("LaunchScreen"),
            "UISupportedInterfaceOrientations": uiSupportedInterfaceOrientations,
            "UTExportedTypeDeclarations": utExportedTypeDeclarations,
            "NSAppTransportSecurity": nsAppTransportSecurity,
            "UTImportedTypeDeclarations": utImportedTypeDeclarations,
            "LSApplicationQueriesSchemes": .array([.string("waze"), .string("comgooglemaps")])
        ]
                
        let customPlistValuesForExtendingDefault = Helpers.customPlistValuesForExtendingDefault(appType: appType)
        
        let allPlistValuesForExtendingDefault = standardPlistValuesForExtendingDefault.merging(customPlistValuesForExtendingDefault, uniquingKeysWith: { _, _ in
            fatalError("Duplicate Info.plist keys")
        })
        
        let infoPlist: InfoPlist = .extendingDefault(with: allPlistValuesForExtendingDefault)
        
        return infoPlist
        
    }
    
    
    public static func forOlvidShareExtension(appType: OlvidAppType) -> Self {
        
        let shareExtensionActivationRule: String = Helpers.shareExtensionActivationRule
        
        let nsExtensionAttributes: Plist.Value = .dictionary([
            "IntentsSupported": .array([.string("INSendMessageIntent")]),
            "NSExtensionActivationRule": .string(shareExtensionActivationRule)
        ])
        
        let nsExtension: Plist.Value = .dictionary([
            "NSExtensionPointIdentifier": .string("com.apple.share-services"),
            "NSExtensionPrincipalClass": .string("$(PRODUCT_MODULE_NAME).ShareViewController"),
            "NSExtensionAttributes": nsExtensionAttributes
        ])
        
        let standardPlistValuesForExtendingDefault: [String : ProjectDescription.Plist.Value] = [
            "NSExtension": nsExtension,
            "CFBundleShortVersionString": .string(Version.marketingVersion),
            "CFBundleVersion": .string(Version.currentProjectVersion),
            "NSHumanReadableCopyright": .string(Constant.nsHumanReadableCopyrightValue),
            "CFBundleDisplayName": .string(Constant.olvidBundleDisplayName(for: appType).appending("-ShareExtension")),
        ]
        
        let customPlistValuesForExtendingDefault = Helpers.customPlistValuesForExtendingDefault(appType: appType)
        
        let allPlistValuesForExtendingDefault = standardPlistValuesForExtendingDefault.merging(customPlistValuesForExtendingDefault, uniquingKeysWith: { _, _ in
            fatalError("Duplicate Info.plist keys")
        })

        let infoPlist: InfoPlist = .extendingDefault(with: allPlistValuesForExtendingDefault)
        
        return infoPlist
    }
    
    
    public static func forOlvidNotificationServiceExtension(appType: OlvidAppType) -> Self {
        
        let nsExtension: Plist.Value = .dictionary([
            "NSExtensionPointIdentifier": .string("com.apple.usernotifications.service"),
            "NSExtensionPrincipalClass": .string("$(PRODUCT_MODULE_NAME).NotificationService"),
        ])
        
        let standardPlistValuesForExtendingDefault: [String : ProjectDescription.Plist.Value] = [
            "NSExtension": nsExtension,
            "CFBundleShortVersionString": .string(Version.marketingVersion),
            "CFBundleVersion": .string(Version.currentProjectVersion),
            "NSHumanReadableCopyright": .init(stringLiteral: Constant.nsHumanReadableCopyrightValue),
            "CFBundleDisplayName": .string(Constant.olvidBundleDisplayName(for: appType).appending("-NotificationServiceExtension")),
        ]
        
        let customPlistValuesForExtendingDefault = Helpers.customPlistValuesForExtendingDefault(appType: appType)
        
        let allPlistValuesForExtendingDefault = standardPlistValuesForExtendingDefault.merging(customPlistValuesForExtendingDefault, uniquingKeysWith: { _, _ in
            fatalError("Duplicate Info.plist keys")
        })

        let infoPlist: InfoPlist = .extendingDefault(with: allPlistValuesForExtendingDefault)
        
        return infoPlist

    }
    
    
    public static func forOlvidIntentsServiceExtension(appType: OlvidAppType) -> Self {
        
        let nsExtension: Plist.Value = .dictionary([
            "NSExtensionAttributes": .dictionary([
                "IntentsRestrictedWhileLocked": .array([]),
                "IntentsSupported": .array([
                    .string("INStartCallIntent"),
                ]),
            ]),
            "NSExtensionPointIdentifier": .string("com.apple.intents-service"),
            "NSExtensionPrincipalClass": .string("$(PRODUCT_MODULE_NAME).IntentHandler"),
        ])
        
        let standardPlistValuesForExtendingDefault: [String : ProjectDescription.Plist.Value] = [
            "NSExtension": nsExtension,
            "CFBundleShortVersionString": .string(Version.marketingVersion),
            "NSHumanReadableCopyright": .string(Constant.nsHumanReadableCopyrightValue),
            "CFBundleVersion": .string(Version.currentProjectVersion),
            "CFBundleDisplayName": .string(Constant.olvidBundleDisplayName(for: appType).appending("-IntentsServiceExtension")),
        ]
        
        let customPlistValuesForExtendingDefault = Helpers.customPlistValuesForExtendingDefault(appType: appType)
        
        let allPlistValuesForExtendingDefault = standardPlistValuesForExtendingDefault.merging(customPlistValuesForExtendingDefault, uniquingKeysWith: { _, _ in
            fatalError("Duplicate Info.plist keys")
        })

        let infoPlist: InfoPlist = .extendingDefault(with: allPlistValuesForExtendingDefault)
        
        return infoPlist

    }
        
}


// MARK: - Helpers

fileprivate struct Helpers {
    
    static func customPlistValuesForExtendingDefault(appType: OlvidAppType) -> [String : ProjectDescription.Plist.Value] {
        [
            "OBV_APP_TYPE": .string(appType.description),
            "OBV_APP_GROUP_IDENTIFIER": .string(Constant.appGroupIdentifier(for: appType)),
            "OBV_HOST_FOR_CONFIGURATIONS": .string(OlvidHost.olvidConfiguration.description),
            "OBV_HOST_FOR_INVITATIONS": .string(OlvidHost.invitation.description),
            "OBV_HOST_FOR_OPENID_REDIRECT": .string(OlvidHost.openIdRedirect(appType: appType).description),
            "OBV_SERVER_URL": .string(Constant.olvidDistributionServerInfos(appType: appType).url),
            "OBV_REMOTE_NOTIFICATION_BYTE_IDENTIFIER_FOR_SERVER_MAC": .string(Constant.olvidDistributionServerInfos(appType: appType).remoteNotificationByteIdentifierForServer.mac),
            "OBV_REMOTE_NOTIFICATION_BYTE_IDENTIFIER_FOR_SERVER_IPHONE": .string(Constant.olvidDistributionServerInfos(appType: appType).remoteNotificationByteIdentifierForServer.iPhone),
        ]
    }

    
    static let shareExtensionActivationRule: String = """
SUBQUERY (
  extensionItems,
  $extensionItem,
  SUBQUERY (
    $extensionItem.attachments,
    $attachment,
    ANY $attachment.registeredTypeIdentifiers UTI-CONFORMS-TO "public.data" ||
    ANY $attachment.registeredTypeIdentifiers UTI-CONFORMS-TO "public.url" ||
    ANY $attachment.registeredTypeIdentifiers UTI-CONFORMS-TO "com.apple.pkpass"
  ).@count >= 1
).@count == 1
OR (
  SUBQUERY (
    extensionItems,
    $extensionItem,
    SUBQUERY (
      $extensionItem.attachments,
      $attachment,
      ANY $attachment.registeredTypeIdentifiers UTI-CONFORMS-TO "public.data" ||
      ANY $attachment.registeredTypeIdentifiers UTI-CONFORMS-TO "public.url" ||
      ANY $attachment.registeredTypeIdentifiers UTI-CONFORMS-TO "com.apple.pkpass"
    ).@count >= 1
  ).@count == 2
  AND SUBQUERY (
    extensionItems,
    $extensionItem,
    SUBQUERY (
      $extensionItem.attachments,
      $attachment,
      ANY $attachment.registeredTypeIdentifiers UTI-EQUALS "public.url"
    ).@count >= 1
  ).@count == 1
)
"""
    
}
