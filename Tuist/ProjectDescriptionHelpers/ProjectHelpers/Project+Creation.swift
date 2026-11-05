import ProjectDescription


extension Project {
    
    public static func createProjectForFramework(packages: [ProjectDescription.Package] = [], frameworkTarget: Target, frameworkTestsTarget: Target? = nil) -> Self {
        
        let automaticSchemesOptions = Options.AutomaticSchemesOptions.enabled(
            targetSchemesGrouping: .singleScheme,
            codeCoverageEnabled: true,
            testingOptions: .parallelizable,
            testLanguage: nil,
            testRegion: nil,
            testScreenCaptureFormat: .screenshots,
            runLanguage: nil,
            runRegion: nil)
        
        let options = Options.options(
            automaticSchemesOptions: automaticSchemesOptions,
            defaultKnownRegions: Constant.availableRegions,
            developmentRegion: Constant.developmentRegion)
        
        var targets = [frameworkTarget]
        if let frameworkTestsTarget {
            targets += [frameworkTestsTarget]
        }
        
        return .init(name: frameworkTarget.name, // We use the target name as the project name
                     organizationName: Constant.organizationName,
                     options: options,
                     packages: packages,
                     settings: nil,
                     targets: targets,
                     schemes: [], // Schemes are generated automatically (see automaticSchemesOptions above)
                     fileHeaderTemplate: .string(Constant.fileHeaderTemplate),
                     additionalFiles: [],
                     resourceSynthesizers: [])
        
    }
    
    public static func createProjectForFrameworks(projectName: String, packages: [ProjectDescription.Package] = [], frameworkTargets: [(target: Target, testsTarget: Target?)]) -> Self {
        
        let automaticSchemesOptions = Options.AutomaticSchemesOptions.enabled(
            targetSchemesGrouping: .singleScheme,
            codeCoverageEnabled: true,
            testingOptions: .parallelizable,
            testLanguage: nil,
            testRegion: nil,
            testScreenCaptureFormat: .screenshots,
            runLanguage: nil,
            runRegion: nil)
        
        let options = Options.options(
            automaticSchemesOptions: automaticSchemesOptions,
            defaultKnownRegions: Constant.availableRegions,
            developmentRegion: Constant.developmentRegion)
        
        let targets = frameworkTargets.map({ $0.target }) + frameworkTargets.compactMap({ $0.testsTarget })

        return .init(name: projectName,
                     organizationName: Constant.organizationName,
                     options: options,
                     packages: packages,
                     settings: nil,
                     targets: targets,
                     schemes: [], // Schemes are generated automatically (see automaticSchemesOptions above)
                     fileHeaderTemplate: .string(Constant.fileHeaderTemplate),
                     additionalFiles: [],
                     resourceSynthesizers: [])
        
    }

    
    /// Shall only be used in very specific cases when creating a project for a framework, such as legacy projects. Use ``static createProjectForFramework(packages:frameworkTarget:frameworkTestsTarget:)`` instead.
    public static func createProjectForFrameworkLegacy(name: String, packages: [ProjectDescription.Package] = [], targets: [Target]) -> Self {
        
        let automaticSchemesOptions = Options.AutomaticSchemesOptions.enabled(
            targetSchemesGrouping: .notGrouped,
            codeCoverageEnabled: false,
            testingOptions: .parallelizable,
            testLanguage: nil,
            testRegion: nil,
            testScreenCaptureFormat: .screenshots,
            runLanguage: nil,
            runRegion: nil)
        
        let options = Options.options(
            automaticSchemesOptions: automaticSchemesOptions,
            defaultKnownRegions: Constant.availableRegions,
            developmentRegion: Constant.developmentRegion)

        return .init(name: name,
                     organizationName: Constant.organizationName,
                     options: options,
                     packages: packages,
                     settings: nil,
                     targets: targets,
                     schemes: [], // Schemes are generated automatically (see automaticSchemesOptions above)
                     fileHeaderTemplate: .string(Constant.fileHeaderTemplate),
                     additionalFiles: [],
                     resourceSynthesizers: [])

    }
    
    
    public static func createProjectForApp(name: String, packages: [ProjectDescription.Package] = [], targets: [Target]) -> Self {
        
        let options = Options.options(
            automaticSchemesOptions: .disabled,
            defaultKnownRegions: Constant.availableRegions,
            developmentRegion: Constant.developmentRegion)
        
        let schemes: [Scheme] = schemesForAppProject(for: targets)
        
        let settings: Settings = .settingsOfMainAppProject()

        return .init(name: name,
                     organizationName: Constant.organizationName,
                     options: options,
                     packages: packages,
                     settings: settings,
                     targets: targets,
                     schemes: schemes,
                     fileHeaderTemplate: .string(Constant.fileHeaderTemplate),
                     additionalFiles: [],
                     resourceSynthesizers: [])
        
    }
    
    
    
    
    private static func schemesForAppProject(for targets: [Target]) -> [ProjectDescription.Scheme] {
        
        let schemes: [[Scheme]] = targets.map {
            
            switch $0.product {
                
            case .app:
                
                let runActionOptions = RunActionOptions.options(
                    storeKitConfigurationPath: .relativeToManifest("App/NewStoreKitConfiguration.storekit"),
                    enableGPUFrameCaptureMode: .default
                )
                
                let environmentVariables: [String: EnvironmentVariable] = [
                    "SQLITE_ENABLE_THREAD_ASSERTIONS": .init(stringLiteral: "1"),
                    "SQLITE_ENABLE_FILE_ASSERTIONS": .init(stringLiteral: "1"),
                ]
                
                let launchArguments: [LaunchArgument] = [
                    .launchArgument(name: "-com.apple.CoreData.MigrationDebug 1", isEnabled: true),
                    .launchArgument(name: "-com.apple.CoreData.SQLDebug 1", isEnabled: false),
                    .launchArgument(name: "-com.apple.TipKit.ResetDatastore 1", isEnabled: false),
                    .launchArgument(name: "-com.apple.CoreData.ConcurrencyDebug 1", isEnabled: true),
                    .launchArgument(name: "-NSShowNonLocalizedStrings YES", isEnabled: true),
                ]
                
                let arguments: Arguments = .arguments(environmentVariables: environmentVariables, launchArguments: launchArguments)
                
                let appScheme: Scheme = .scheme(
                    name: $0.name,
                    shared: true,
                    hidden: false,
                    buildAction: .buildAction(targets: [.init(stringLiteral: $0.name)]),
                    testAction: nil,
                    runAction: .runAction(attachDebugger: true,
                                          executable: .target($0.name),
                                          arguments: arguments,
                                          options: runActionOptions,
                                          diagnosticsOptions: .options(addressSanitizerEnabled: false,
                                                                       detectStackUseAfterReturnEnabled: false,
                                                                       threadSanitizerEnabled: false,
                                                                       mainThreadCheckerEnabled: true,
                                                                       performanceAntipatternCheckerEnabled: false),
                                          launchStyle: .automatically))
                
                
                let schemes: [Scheme] = [
                    appScheme,
                ]
                
                return schemes

            case .unitTests:
                
                /// The app's own unit tests get a scheme of their own rather than a test action on one of the two app
                /// schemes: the target hosts no app, so it belongs to neither of them, and a scheme of its own is what
                /// makes `xcodebuild test -scheme ...` reach it.
                let testsScheme: Scheme = .scheme(
                    name: $0.name,
                    shared: true,
                    hidden: false,
                    buildAction: .buildAction(targets: [.init(stringLiteral: $0.name)]),
                    testAction: .targets([.testableTarget(target: .init(stringLiteral: $0.name))]),
                    runAction: nil,
                    archiveAction: nil,
                    profileAction: nil,
                    analyzeAction: nil)
                
                return [testsScheme]
                
            case .appExtension:

                // An app extension cannot be installed on its own — it ships embedded in its host app.
                // The run executable must therefore be the host app, not the extension: pointing the
                // scheme at the extension makes Xcode try to install the `.appex` standalone, which fails
                // with "…already installed…" because a copy is already embedded in the installed app.
                // Launching the host app installs it (with the embedded extension); since the extension
                // remains a build target and `attachDebugger` is set, Xcode attaches to it when it is
                // spawned (share the content from another app into Olvid to trigger it).
                let hostAppName = $0.name.hasSuffix("-Development")
                    ? Constant.olvidTargetNames(for: .development).app
                    : Constant.olvidTargetNames(for: .production).app

                let appExtensionScheme: Scheme = .scheme(
                    name: $0.name,
                    shared: true,
                    hidden: false,
                    buildAction: .buildAction(targets: [.init(stringLiteral: $0.name),
                                                        .init(stringLiteral: hostAppName)]),
                    testAction: nil,
                    runAction: .runAction(attachDebugger: true,
                                          executable: .target(hostAppName),
                                          arguments: nil,
                                          diagnosticsOptions: .options(addressSanitizerEnabled: false,
                                                                       detectStackUseAfterReturnEnabled: false,
                                                                       threadSanitizerEnabled: false,
                                                                       mainThreadCheckerEnabled: true,
                                                                       performanceAntipatternCheckerEnabled: false),
                                          launchStyle: .automatically),
                    archiveAction: nil,
                    profileAction: nil,
                    analyzeAction: nil)

                return [
                    appExtensionScheme,
                ]
                
            case .appClip,
                    .bundle,
                    .commandLineTool,
                    .dynamicLibrary,
                    .messagesExtension,
                    .staticFramework,
                    .staticLibrary,
                    .stickerPackExtension,
                    .systemExtension,
                    .tvTopShelfExtension,
                    .uiTests,
                    .macro,
                    .watch2App,
                    .watch2Extension,
                    .xpc,
                    .framework,
                    .extensionKitExtension:
                fatalError("please handle me, case: \($0.product)")

            @unknown default:
                fatalError("please handle me, case: \($0.product)")
            }
            
        }
        
        return schemes.flatMap({$0})
        
    }

}
