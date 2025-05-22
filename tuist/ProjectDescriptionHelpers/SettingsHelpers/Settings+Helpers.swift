import ProjectDescription

extension Dictionary where Key == String, Value == ProjectDescription.SettingValue {
    
//    func swiftLanguageVersion6() -> Self {
//        merging(["SWIFT_VERSION": .init(stringLiteral: "6.0")])
//    }
    
    func developmentAssets(_ previewContent: String? = nil) -> Self {
        if let previewContent {
            return merging(["DEVELOPMENT_ASSET_PATHS": .init(stringLiteral: previewContent)])
        } else {
            return self
        }
    }
    
    /// When enabled, the Swift compiler will be used to extract Swift string literal and interpolation LocalizedStringKey and LocalizationKey types during localization export.
    ///
    /// See: https://developer.apple.com/documentation/xcode/build-settings-reference#Use-Compiler-to-Extract-Swift-Strings
    func useCompilerToExtractSwiftStrings(_ bool: Bool) -> Self {
        merging(["SWIFT_EMIT_LOC_STRINGS": .init(booleanLiteral: bool)])
    }
    
    
    /// Automatically generate an Info.plist file.
    ///
    /// See: https://developer.apple.com/documentation/xcode/build-settings-reference#Generate-Infoplist-File
    func generateInfoPlistFile(_ bool: Bool) -> Self {
        merging(["GENERATE_INFOPLIST_FILE": .init(booleanLiteral: bool)])
    }
    
    
    /// Use no versioning system.
    ///
    /// See: https://developer.apple.com/documentation/xcode/build-settings-reference#Versioning-System
    func disableAppleGenericVersioning() -> Self {
        return merging(["VERSIONING_SYSTEM": ""])
    }
    
    
    /// When enabled, this causes the compiler and linker to disallow use of APIs that are not available to app extensions and to disallow linking to frameworks that have not been built with this setting enabled.
    ///
    /// See: https://developer.apple.com/documentation/xcode/build-settings-reference#Require-Only-App-Extension-Safe-API
    func requireOnlyAppExtensionSafeAPI(_ bool: Bool) -> Self {
        if bool {
            return merging(["APPLICATION_EXTENSION_API_ONLY": .init(booleanLiteral: bool)])
        } else {
            return self
        }
    }
    
    /// The name to use for the source code module constructed for this target, and which will be used to import the module in implementation source files. Must be a valid identifier.
    ///
    /// See: https://developer.apple.com/documentation/xcode/build-settings-reference#Product-Module-Name
    func enableModuleDefinition(moduleName: String) -> Self {
        return merging([
            "DEFINES_MODULE": true,
            "PRODUCT_MODULE_NAME": .init(stringLiteral: moduleName)
        ])
    }
    
    /// When enabled, Xcode will automatically derive a bundle identifier for this target from its original bundle identifier when it’s building for Mac Catalyst.
    ///
    /// See: https://developer.apple.com/documentation/xcode/build-settings-reference#Derive-Mac-Catalyst-Product-Bundle-Identifier
    func deriveMacCatalystProductBundleIdentifier(_ bool: Bool) -> Self {
        return merging(["DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER": .init(booleanLiteral: bool)])
    }
    
    
    /// This setting defines the user-visible version of the project.
    /// When `GENERATE_INFOPLIST_FILE` is enabled, sets the value of the `CFBundleShortVersionString` key in the Info.plist file to the value of this build setting.
    ///
    /// See: https://developer.apple.com/documentation/xcode/build-settings-reference#Marketing-Version
    func marketingVersion(_ string: String) -> Self {
        return merging(["MARKETING_VERSION": .string(string)])
    }
    
    
    /// This setting defines the current version of the project. The value must be a integer or floating point number, such as 57 or 365.8.
    /// When `GENERATE_INFOPLIST_FILE` is enabled, sets the value of the `CFBundleVersion` key in the Info.plist file to the value of this build setting.
    ///
    /// See: https://developer.apple.com/documentation/xcode/build-settings-reference#Current-Project-Version
    func  currentProjectVersion(_ string: String) -> Self {
        return merging(["CURRENT_PROJECT_VERSION": .string(string)])
    }
    
    
    /// Support building this target for Mac Catalyst.
    ///
    /// See: https://developer.apple.com/documentation/xcode/build-settings-reference#Supports-Mac-Catalyst
    func supportsMacCatalyst(_ bool: Bool) -> Self {
        return merging(["SUPPORTS_MACCATALYST": .init(booleanLiteral: bool)])
    }
    
    
    /// Enables strict concurrency checking to produce warnings for possible data races. This is always ‘complete’ when in the Swift 6 language mode and produces errors instead of warnings.
    ///
    /// See: https://developer.apple.com/documentation/xcode/build-settings-reference#Strict-Concurrency-Checking
    func enableCompleteStrictConcurrencyChecking() -> Self {
        return merging(["SWIFT_STRICT_CONCURRENCY": .string("complete")])
    }
    
    
    /// Changes #file to evaluate to a string literal of the format `<module-name>/<file-name>`, with the existing behavior preserved in a new `#filePath`. This is always enabled when in the Swift 6 language mode.
    ///
    /// See: https://developer.apple.com/documentation/xcode/build-settings-reference#Concise-Magic-File
    func conciseMagicFile() -> Self {
        return merging(["SWIFT_UPCOMING_FEATURE_CONCISE_MAGIC_FILE": .init(booleanLiteral: true)])
    }
    
    
    /// Causes any use of `@UIApplicationMain` or `@NSApplicationMain` to produce a warning (use `@main` instead). This is always enabled when in the Swift 6 language mode and an error instead of a warning.
    ///
    /// See: https://developer.apple.com/documentation/xcode/build-settings-reference#Deprecate-Application-Main
    func deprecateApplicationMain() -> Self {
        return merging(["SWIFT_UPCOMING_FEATURE_DEPRECATE_APPLICATION_MAIN": .init(booleanLiteral: true)])
    }
    
    
    /// Removes inferred actor isolation inference from property wrappers. This is always enabled when in the Swift 6 language mode.
    ///
    /// See: https://developer.apple.com/documentation/xcode/build-settings-reference#Disable-Outward-Actor-Isolation-Inference
    func disableOutwardActorIsolationInference() -> Self {
        return merging(["SWIFT_UPCOMING_FEATURE_DISABLE_OUTWARD_ACTOR_ISOLATION": .init(booleanLiteral: true)])
    }
    
    
    /// Updates trailing closures to be evaluated such that arguments are matched forwards instead of backwards. This is always enabled when in the Swift 6 language mode.
    ///
    /// See: https://developer.apple.com/documentation/xcode/build-settings-reference#Forward-Trailing-Closures
    func forwardTrailingClosures() -> Self {
        return merging(["SWIFT_UPCOMING_FEATURE_FORWARD_TRAILING_CLOSURES": .init(booleanLiteral: true)])
    }
    
    
    /// Adds a warning for global variables that are neither isolated to a global actor or are not both immutable and Sendable. This is always enabled when in the Swift 6 language mode and an error instead of a warning.
    ///
    /// See: https://developer.apple.com/documentation/xcode/build-settings-reference#Isolated-Global-Variables
    func isolatedGlobalVariables() -> Self {
        return merging(["SWIFT_UPCOMING_FEATURE_GLOBAL_CONCURRENCY": .init(booleanLiteral: true)])
    }
    
    
    /// Enables passing an existential where a generic is expected. This is always enabled when in the Swift 6 language mode.
    ///
    /// See: https://developer.apple.com/documentation/xcode/build-settings-reference#Implicitly-Opened-Existentials
    func implicitlyOpenedExistentials() -> Self {
        return merging(["SWIFT_UPCOMING_FEATURE_IMPLICIT_OPEN_EXISTENTIALS": .init(booleanLiteral: true)])
    }
    
    
    /// Synthesizes placeholder types to represent forward declared Objective-C interfaces and protocols. This is always enabled when in the Swift 6 language mode.
    ///
    /// See: https://developer.apple.com/documentation/xcode/build-settings-reference#Import-Objective-C-Forward-Declarations
    func importObjectiveCForwardDeclarations() -> Self {
        return merging(["SWIFT_UPCOMING_FEATURE_IMPORT_OBJC_FORWARD_DECLS": .init(booleanLiteral: true)])
    }
    
    
    /// Adds sendability inference for partial and unapplied methods, and allows specifying whether a key path literal is Sendable. This is always enabled when in the Swift 6 language mode.
    ///
    /// See: https://developer.apple.com/documentation/xcode/build-settings-reference#Infer-Sendable-for-Methods-and-Key-Path-Literals
    func inferSendableForMethodsAndKeyPathLiterals() -> Self {
        return merging(["SWIFT_UPCOMING_FEATURE_INFER_SENDABLE_FROM_CAPTURES": .init(booleanLiteral: true)])
    }
    

    /// Switches the default accessibility of module imports to internal rather than public.
    ///
    /// See: https://developer.apple.com/documentation/xcode/build-settings-reference#Default-Internal-Imports
    func defaultInternalImports() -> Self {
        return merging(["SWIFT_UPCOMING_FEATURE_INTERNAL_IMPORTS_BY_DEFAULT": .init(booleanLiteral: true)])
    }
    
    
    /// Adds actor isolation for default values, matching its enclosing function or stored property. This is always enabled when in the Swift 6 language mode.
    ///
    /// See: https://developer.apple.com/documentation/xcode/build-settings-reference#Isolated-Default-Values
    func isolatedDefaultValues() -> Self {
        return merging(["SWIFT_UPCOMING_FEATURE_ISOLATED_DEFAULT_VALUES": .init(booleanLiteral: true)])
    }
    
    /// Enable passing non-Sendable values over isolation boundaries when there’s no possibility of concurrent access. This is always enabled when in the Swift 6 language mode.
    ///
    /// See: https://developer.apple.com/documentation/xcode/build-settings-reference#Region-Based-Isolation
    func regionBasedIsolation() -> Self {
        return merging(["SWIFT_UPCOMING_FEATURE_REGION_BASED_ISOLATION": .init(booleanLiteral: true)])
    }
    
    
    /// If enabled, the build system will sandbox user scripts to disallow undeclared input/output dependencies.
    ///
    /// See: https://developer.apple.com/documentation/xcode/build-settings-reference#User-Script-Sandboxing
    func enableUserScriptSandboxing(_ bool: Bool) -> Self {
        merging(["ENABLE_USER_SCRIPT_SANDBOXING": .init(booleanLiteral: bool)])
    }
    
}
