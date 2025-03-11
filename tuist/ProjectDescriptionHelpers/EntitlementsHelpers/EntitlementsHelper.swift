import ProjectDescription

extension Entitlements {
    
    public static func forMainApp(appType: OlvidAppType) -> Self {

        // The environment for push notifications.
        // See: https://developer.apple.com/documentation/bundleresources/entitlements/aps-environment
        let apsEnvironment: Plist.Value
        switch appType {
        case .development:
            apsEnvironment = .string("development")
        case .production:
            apsEnvironment = .string("production")
        }
        
        let associatedDomains: Plist.Value = .array([
            .string("applinks:\(OlvidHost.invitation)"),
            .string("applinks:\(OlvidHost.olvidConfiguration)"),
            .string("applinks:\(OlvidHost.openIdRedirect(appType: appType))"),
        ])
        
        let iCloudContainerIdentifiers: Plist.Value = .array([
            .string(Constant.iCloudContainerIdentifierForOlvidBackups)
        ])
        
        return .dictionary([
            "aps-environment": apsEnvironment,
            "com.apple.developer.associated-domains": associatedDomains,
            "com.apple.developer.icloud-container-identifiers": iCloudContainerIdentifiers,
            "com.apple.developer.icloud-services": .array([.string("CloudKit")]),
            "com.apple.developer.siri": .boolean(true),
            "com.apple.developer.usernotifications.communication": .boolean(true),
            "com.apple.security.app-sandbox": .boolean(true),
            "com.apple.security.application-groups": .array([
                .string(Constant.appGroupIdentifier(for: appType)),
            ]),
            "com.apple.security.device.audio-input": .boolean(true),
            "com.apple.security.device.camera": .boolean(true),
            "com.apple.security.files.user-selected.read-write": .boolean(true),
            "com.apple.security.network.client": .boolean(true),
            "com.apple.security.network.server": .boolean(true), // macOS key, required by WebRTC
            "com.apple.security.personal-information.photos-library": .boolean(true),
            "com.apple.security.personal-information.location": .boolean(true)
        ])
    }
    
    
    public static func forShareExtension(appType: OlvidAppType) -> Self {
        return .dictionary([
            "com.apple.security.app-sandbox": .boolean(true),
            "com.apple.security.application-groups": .array([
                .string(Constant.appGroupIdentifier(for: appType)),
            ]),
            "com.apple.security.network.client": .boolean(true),
        ])
    }
    
    
    public static func forNotificationServiceExtension(appType: OlvidAppType) -> Self {
        return .dictionary([
            "com.apple.developer.usernotifications.filtering": .boolean(true),
            "com.apple.security.app-sandbox": .boolean(true),
            "com.apple.security.application-groups": .array([
                .string(Constant.appGroupIdentifier(for: appType)),
            ]),
            "com.apple.security.network.client": .boolean(true),
        ])
    }
    
    
    public static func forIntentsServiceExtension() -> Self {
        return .dictionary([
            "com.apple.security.app-sandbox": .boolean(true),
        ])
    }
    
}
