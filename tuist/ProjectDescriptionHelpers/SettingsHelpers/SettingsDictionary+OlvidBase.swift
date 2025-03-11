import ProjectDescription


extension SettingsDictionary {
    
    public static func olvidBaseSettingsForMainAppTarget(appType: OlvidAppType) -> SettingsDictionary {
        
        let base = Self.olvidBaseSettings()
        
        let baseForApp = base.merging([
            "ASSETCATALOG_COMPILER_APPICON_NAME": .string(Constant.olvidAppIconName(for: appType)),
            "INFOPLIST_KEY_LSApplicationCategoryType": .string(Constant.appCategory),
            "INFOPLIST_KEY_CFBundleDisplayName": .string(Constant.olvidBundleDisplayName(for: appType)),
        ])

        return baseForApp
        
    }
    
    
    public static func olvidBaseSettingsOfAppExtensionTarget() -> SettingsDictionary {
        
        let base = Self.olvidBaseSettings()

        let baseForExtensionTarget = base
            .requireOnlyAppExtensionSafeAPI(true)
        
        return baseForExtensionTarget
        
    }
    

    public static func olvidBaseSettings(prepareForSwift6: Bool = false, enableSwift6: Bool = false) -> SettingsDictionary {
        
        let base: SettingsDictionary = [:]
            .supportsMacCatalyst(true)
            .deriveMacCatalystProductBundleIdentifier(false)
            .marketingVersion(Version.marketingVersion)
            .currentProjectVersion(Version.currentProjectVersion)
            .useCompilerToExtractSwiftStrings(true)
            .enableUserScriptSandboxing(true)
            .generateInfoPlistFile(false)
            .disableAppleGenericVersioning()
            .automaticCodeSigning(devTeam: Constant.devTeam)
        
        if enableSwift6 {
            return base
                .swiftVersion("6.0")
        } else if prepareForSwift6 {
            return base
                .enableCompleteStrictConcurrencyChecking()
                .conciseMagicFile()
                .deprecateApplicationMain()
                .disableOutwardActorIsolationInference()
                .forwardTrailingClosures()
                .isolatedGlobalVariables()
                .implicitlyOpenedExistentials()
                .importObjectiveCForwardDeclarations()
                .inferSendableForMethodsAndKeyPathLiterals()
                //.defaultInternalImports()
                .isolatedDefaultValues()
                .regionBasedIsolation()
        } else {
            return base
        }
        
        
    }
    
}
