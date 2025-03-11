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
                    storeKitConfigurationPath: .relativeToManifest("App/TestConfiguration.storekit"),
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

            case .appExtension:
                
                let appExtensionScheme: Scheme = .scheme(
                    name: $0.name,
                    shared: true,
                    hidden: false,
                    buildAction: .buildAction(targets: [.init(stringLiteral: $0.name)]),
                    testAction: nil,
                    runAction: .runAction(attachDebugger: true,
                                          executable: .target($0.name),
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
                    .unitTests,
                    .extensionKitExtension:
                fatalError("please handle me, case: \($0.product)")

            @unknown default:
                fatalError("please handle me, case: \($0.product)")
            }
            
        }
        
        return schemes.flatMap({$0})
        
    }

}
