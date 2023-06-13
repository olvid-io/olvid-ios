import ProjectDescription
import Foundation

internal extension SettingsDictionary {
    func applicationExtensionAPIOnly(_ value: Bool) -> Self {
        if value {
            return merging(["APPLICATION_EXTENSION_API_ONLY": .init(booleanLiteral: value)])
        } else {
            return self
        }
    }

    func enableModuleDefinition(moduleName: String) -> Self {
        return merging([
            "DEFINES_MODULE": true,
            "PRODUCT_MODULE_NAME": .init(stringLiteral: moduleName)
        ])
    }

    func iOSDeploymentTargetVersion(_ version: String) -> Self {
        return merging(["IPHONEOS_DEPLOYMENT_TARGET": .string(version)])
    }

    func disableInfoPlistGeneration() -> Self {
        return merging(["GENERATE_INFOPLIST_FILE": false])
    }

    func disableSwiftLocalizableStringsExtraction() -> Self {
        return merging(["SWIFT_EMIT_LOC_STRINGS": false])
    }

    func assetCompilerAppIcon(name: String) -> Self {
        return merging([
            "ASSETCATALOG_COMPILER_APPICON_NAME": .string(name)
        ])
    }

    func setupDisplayNameVariables() -> Self {
        return merging([
            "OBV_BUNDLE_DISPLAY_NAME": "Olvid$(OLVID_PRODUCT_BUNDLE_DISPLAY_NAME_SERVER_SUFFIX)",
            "OBV_BUNDLE_DISPLAY_NAME_FOR_SHARE_EXTENSION": "Olvid$(OLVID_PRODUCT_BUNDLE_DISPLAY_NAME_SERVER_SUFFIX)",
            "OBV_BUNDLE_DISPLAY_NAME_FOR_NOTIFICATION_SERVICE_EXTENSION": "Olvid$(OLVID_PRODUCT_BUNDLE_DISPLAY_NAME_SERVER_SUFFIX)",
            "OBV_BUNDLE_DISPLAY_NAME_FOR_INTENTS_EXTENSION": "Olvid$(OLVID_PRODUCT_BUNDLE_DISPLAY_NAME_SERVER_SUFFIX)",
        ])
    }

    /// Injects various base configuration values
    func injectBaseValues() -> Self {
        return merging([
            "OLVID_BASE_SLASH": "/"
        ])
    }

    func automaticCodeSigning(devTeam: String?) -> Self {
        guard let devTeam = devTeam else {
            return self
        }

        return automaticCodeSigning(devTeam: devTeam)
    }

    func excludedFileNames(_ files: String...) -> Self {
        return merging([
            "EXCLUDED_SOURCE_FILE_NAMES": .array(files)
        ])
    }

    func disableAppleGenericVersioning() -> Self {
        return merging([
            "VERSIONING_SYSTEM": ""
        ])
    }
}

/// Extension for default values related to our configurations and default settings
///
/// - SeeAlso:
///   - `Configuration`
///   - `DefaultSettings`
private extension Settings {
    /// Our default configurations
    static let defaultConfigurations: [Configuration] = {
        return [.appStoreDebug,
                .appStoreRelease]
    }()

    private static let _keysToExcludeForProjectRecommendedDefaultSettings: Set<String> = []

    private static let _keysToExcludeForLibraryTargetsFromRecommendedDefaultSettings: Set<String> = [
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS",
    ]

    private static let _keysToExcludeForUITargetsFromRecommendedDefaultSettings: Set<String> = [
        "ASSETCATALOG_COMPILER_APPICON_NAME"
    ]

    static let defaultSettingsForProjects: DefaultSettings = {
        return .recommended(excluding: _keysToExcludeForProjectRecommendedDefaultSettings)
    }()


    static let defaultSettingsForLibraryTargets: DefaultSettings = {
        return .recommended(excluding: _keysToExcludeForProjectRecommendedDefaultSettings.union(_keysToExcludeForLibraryTargetsFromRecommendedDefaultSettings))
    }()

    static let defaultSettingsForUITargets: DefaultSettings = {
        return .recommended(excluding: _keysToExcludeForProjectRecommendedDefaultSettings.union(_keysToExcludeForLibraryTargetsFromRecommendedDefaultSettings).union( _keysToExcludeForUITargetsFromRecommendedDefaultSettings))
    }()
}

public extension Settings {
    static func defaultProjectSettings() -> Self {
        return defaultProjectSettings(appending: [:])
    }

    static func defaultProjectSettings(
        appending base: SettingsDictionary,
        iOSDeploymentTargetVersion: String = Constants.iOSDeploymentTargetVersion
    ) -> Self {
        let baseSettings: SettingsDictionary = base
            .injectBaseValues()
            .automaticCodeSigning(devTeam: Constants.developmentTeam)
            .marketingVersion(Constants.marketingVersion)
            .currentProjectVersion(try! Constants.buildNumber)
            .iOSDeploymentTargetVersion(iOSDeploymentTargetVersion)
            .disableInfoPlistGeneration()
            .disableSwiftLocalizableStringsExtraction()
            .swiftActiveCompilationConditions("$(inherited)", "$(OLVID_MODE_SWIFT_ACTIVE_COMPILATION_CONDITIONS)", "$(OLVID_SERVER_SWIFT_ACTIVE_COMPILATION_CONDITIONS)")
            .excludedFileNames("$(inherited)", "$(OLVID_MODE_EXCLUDED_SOURCE_FILE_NAMES)", "$(OLVID_SERVER_EXCLUDED_SOURCE_FILE_NAMES)")
            .disableAppleGenericVersioning()

        return .settings(base: baseSettings,
                         configurations: defaultConfigurations,
                         defaultSettings: defaultSettingsForProjects)
    }

    static func defaultSPMProjectSettings() -> Self {
        return .settings(base: [:],
                         configurations: defaultConfigurations,
                         defaultSettings: defaultSettingsForLibraryTargets)
    }

    static func defaultMainAppTargetSettings() -> Self {
        let baseSettings: SettingsDictionary = [:]
            .assetCompilerAppIcon(name: "AppIcon$(OLVID_ASSETCATALOG_COMPILER_APPICON_NAME_SUFFIX)")
            .setupDisplayNameVariables()

        return .settings(base: baseSettings,
                         configurations: defaultConfigurations,
                         defaultSettings: defaultSettingsForUITargets)
    }

    static func defaultAppExtensionTargetSettings() -> Self {
        let baseSettings: SettingsDictionary = [:]
            .setupDisplayNameVariables()

        return .settings(base: baseSettings,
                         configurations: defaultConfigurations,
                         defaultSettings: defaultSettingsForUITargets)
    }
}

private extension Configuration {
    private static func modeBaseSettings(activeCompilationConditions: String...,
                                         includedSourceFileNames: String...,
                                         excludedSourceFileNames: String...,
                                         enableBonjourInfoPlistAdditions: Bool,
                                         enableRevealInfoPlistAdditions: Bool) -> SettingsDictionary {
        if enableRevealInfoPlistAdditions && !enableBonjourInfoPlistAdditions {
            preconditionFailure("enableBonjourInfoPlistAdditions should be enable if enabling enableRevealInfoPlistAdditions")
        }

        let excludeRevealSourceFilenames: [String]

        if enableRevealInfoPlistAdditions {
            excludeRevealSourceFilenames = []
        } else {
            excludeRevealSourceFilenames = ["Reveal*"]
        }

        return ["OLVID_MODE_SWIFT_ACTIVE_COMPILATION_CONDITIONS": .array(["$(inherited)"] + activeCompilationConditions),
                "OLVID_MODE_INCLUDED_SOURCE_FILE_NAMES": .array(["$(inherited)"] + includedSourceFileNames),
                "OLVID_MODE_EXCLUDED_SOURCE_FILE_NAMES": .array(["$(inherited)"] + excludedSourceFileNames + excludeRevealSourceFilenames),
                "OLVID_ENABLE_INFO_PLIST_BONJOUR_ADDITIONS": .init(booleanLiteral: enableBonjourInfoPlistAdditions)]
    }

    private static func serverBaseSettings(bundleIdentifierSuffix: String,
                                           displayNameSuffix: String,
                                           shareExtensionBundleIdentifier: String,
                                           notificationServiceExtensionBundleIdentifier: String,
                                           intentsExtensionBundleIdentifier: String,
                                           activeCompilationConditions: String...,
                                           harcodedAPIKey: String,
                                           serverURL: String,
                                           includedSourceFileNames: String...,
                                           excludedSourceFileNames: String...,
                                           assetCatalogAppIconNameSuffix: String,
                                           isDevelopmentServerMode: Bool,
                                           appGroupIdentifier: String,
                                           invitationsHost: String,
                                           configurationsHost: String,
                                           openIDRedirectHost: String) -> SettingsDictionary {
        return ["OLVID_PRODUCT_BUNDLE_IDENTIFIER_SERVER_SUFFIX": .string(bundleIdentifierSuffix),
                "OLVID_PRODUCT_BUNDLE_DISPLAY_NAME_SERVER_SUFFIX": .string(displayNameSuffix),
                "OBV_PRODUCT_BUNDLE_IDENTIFIER_FOR_SHARE_EXTENSION": .string(shareExtensionBundleIdentifier),
                "OBV_PRODUCT_BUNDLE_IDENTIFIER_FOR_NOTIFICATION_SERVICE_EXTENSION": .string(notificationServiceExtensionBundleIdentifier),
                "OBV_PRODUCT_BUNDLE_IDENTIFIER_FOR_INTENTS_EXTENSION": .string(intentsExtensionBundleIdentifier),
                "OLVID_SERVER_SWIFT_ACTIVE_COMPILATION_CONDITIONS": .array(["$(inherited)"] + activeCompilationConditions),
                "HARDCODED_API_KEY": .string(harcodedAPIKey),
                "OBV_SERVER_URL": .string(serverURL),
                "OLVID_SERVER_INCLUDED_SOURCE_FILE_NAMES": .array(["$(inherited)"] + includedSourceFileNames),
                "OLVID_SERVER_EXCLUDED_SOURCE_FILE_NAMES": .array(["$(inherited)"] + excludedSourceFileNames),
                "OLVID_ASSETCATALOG_COMPILER_APPICON_NAME_SUFFIX": .string(assetCatalogAppIconNameSuffix),
                "OBV_DEVELOPMENT_MODE": .init(booleanLiteral: isDevelopmentServerMode),
                "OBV_APP_GROUP_IDENTIFIER": .string(appGroupIdentifier),
                "OBV_HOST_FOR_INVITATIONS": .string(invitationsHost),
                "OBV_HOST_FOR_CONFIGURATIONS": .string(configurationsHost),
                "OBV_HOST_FOR_OPENID_REDIRECT": .string(openIDRedirectHost)]
    }

    private static let productionServerBase: SettingsDictionary = {
        return serverBaseSettings(bundleIdentifierSuffix: "",
                                  displayNameSuffix: "",
                                  shareExtensionBundleIdentifier: "io.olvid.messenger.extension-share",
                                  notificationServiceExtensionBundleIdentifier: "io.olvid.messenger.extension-notification-service",
                                  intentsExtensionBundleIdentifier: "io.olvid.messenger.ObvMessengerIntentsExtension",
                                  activeCompilationConditions: "OLVID_SERVER_PRODUCTION",
                                  harcodedAPIKey: "5288afb8-bfe0-2ab9-cb24-7b93a54be5d5",
                                  serverURL: "https://server.olvid.io",
                                  assetCatalogAppIconNameSuffix: "",
                                  isDevelopmentServerMode: false,
                                  appGroupIdentifier: "group.io.olvid.messenger",
                                  invitationsHost: "invitation.olvid.io",
                                  configurationsHost: "configuration.olvid.io",
                                  openIDRedirectHost: "openid-redirect.olvid.io")
    }()

    static let appStoreDebug: Self = .debug(name: .appStoreDebug,
                                            settings: modeBaseSettings(activeCompilationConditions: "DEBUG",
                                                                       excludedSourceFileNames: "RevealServer.xcframework",
                                                                       enableBonjourInfoPlistAdditions: false,
                                                                       enableRevealInfoPlistAdditions: false)
                                                .merging(productionServerBase),
                                            xcconfig: nil)

    static let appStoreRelease: Self = .release(name: .appStoreRelease,
                                                settings: modeBaseSettings(activeCompilationConditions: "RELEASE",
                                                                           excludedSourceFileNames: "RevealServer.xcframework",
                                                                           enableBonjourInfoPlistAdditions: false,
                                                                           enableRevealInfoPlistAdditions: false)
                                                    .merging(productionServerBase),
                                                xcconfig: nil)
}

internal extension ConfigurationName {
    /// AppStore~Debug
    static let appStoreDebug: Self = "AppStore~Debug"

    /// AppStore~Release
    static let appStoreRelease: Self = "AppStore~Release"
}

internal extension Settings {
    static func _baseSwiftLibrarySettings(moduleName: String, isExtensionSafe: Bool) -> Self {
        let settings = SettingsDictionary()
            .applicationExtensionAPIOnly(isExtensionSafe)
            .enableModuleDefinition(moduleName: moduleName)
            .disableAppleGenericVersioning()

        return .settings(base: settings,
                         configurations: defaultConfigurations,
                         defaultSettings: defaultSettingsForLibraryTargets)
    }

    static func _baseSwiftLibraryTestsSettings() -> Self {
        return .settings(base: [:],
                         configurations: defaultConfigurations,
                         defaultSettings: defaultSettingsForLibraryTargets)
    }

    static func _baseFrameworkSettings(
        moduleName: String,
        isExtensionSafe: Bool
    ) -> Self {
        let settings = SettingsDictionary()
            .applicationExtensionAPIOnly(isExtensionSafe)
            .enableModuleDefinition(moduleName: moduleName)
            .disableAppleGenericVersioning()

        return .settings(base: settings,
                         configurations: defaultConfigurations,
                         defaultSettings: defaultSettingsForLibraryTargets)
    }
}
