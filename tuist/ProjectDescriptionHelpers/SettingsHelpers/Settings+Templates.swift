import ProjectDescription


extension Settings {
    
    public static func settingsForFrameworkTarget(prepareForSwift6: Bool = false, enableSwift6: Bool = false) -> Self {
        
        let base: SettingsDictionary = .olvidBaseSettings(prepareForSwift6: prepareForSwift6, enableSwift6: enableSwift6)

        return .settings(base: base,
                         debug: base,
                         release: base,
                         defaultSettings: .recommended)
        
    }
    

    public static func settingsOfMainAppProject() -> Self {
        
        let base: SettingsDictionary = .olvidBaseSettings()
        
        return .settings(base: base,
                         debug: base,
                         release: base,
                         defaultSettings: .recommended)

    }

    
    public static func settingsOfMainAppTarget(appType: OlvidAppType) -> Self {
        
        let base: SettingsDictionary = .olvidBaseSettingsForMainAppTarget(appType: appType)

        return .settings(base: base,
                         debug: base,
                         release: base,
                         defaultSettings: .recommended)

    }
    
    
    public static func settingsOfAppExtensionTarget() -> Self {

        let base: SettingsDictionary = .olvidBaseSettingsOfAppExtensionTarget()

        return .settings(base: base,
                         debug: base,
                         release: base,
                         defaultSettings: .recommended)
        
    }
    
    
    public static func settingsOfObjectiveCLibraryTarget() -> Self {
        
        let base: SettingsDictionary = .olvidBaseSettings()

        return .settings(base: base,
                         debug: base,
                         release: base,
                         defaultSettings: .recommended)

    }
    
    
    public static func settingsOfSwiftLibraryTarget() -> Self {
        
        let base: SettingsDictionary = .olvidBaseSettings()

        return .settings(base: base,
                         debug: base,
                         release: base,
                         defaultSettings: .recommended)

    }

}
