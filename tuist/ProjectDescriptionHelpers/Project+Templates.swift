import ProjectDescription

public extension Project {
    static func createProject(
        name: String,
        packages: [Package],
        targets: [Target],
        shouldEnableDefaultResourceSynthesizers: Bool = false
    ) -> Self {
        return .init(
            name: name,
            organizationName: "Olvid",
            options: defaultOptions(),
            packages: packages,
            settings: .defaultProjectSettings(),
            targets: targets,
            schemes: generateSchemes(for: targets),
            fileHeaderTemplate: .string(Constants.fileHeader),
            resourceSynthesizers: Self.defaultResourceSynthesizers(shouldEnableDefaultResourceSynthesizers: shouldEnableDefaultResourceSynthesizers)
        )
    }

    private static func defaultOptions() -> Project.Options {
        return .options(automaticSchemesOptions: .disabled,
                        defaultKnownRegions: Constants.availableRegions,
                        developmentRegion: Constants.developmentRegion,
                        disableBundleAccessors: false,
                        disableShowEnvironmentVarsInScriptPhases: true,
                        disableSynthesizedResourceAccessors: false,
                        textSettings: .textSettings(usesTabs: false,
                                                    indentWidth: 4,
                                                    tabWidth: 4,
                                                    wrapsLines: true))
    }

    private static func defaultResourceSynthesizers(shouldEnableDefaultResourceSynthesizers: Bool) -> [ResourceSynthesizer] {
        if shouldEnableDefaultResourceSynthesizers {
            return .default
        } else {
            return [] //we're disabling resource synthesizers for now, they need to be cleaned first
        }
    }

    private static func generateSchemes(for targets: [Target]) -> [Scheme] {
        return targets.flatMap {
            switch $0.product {
            case .app:
                let runActionOptions = RunActionOptions.options()

                let runEnvironment: [String: String] = [
                    "SQLITE_ENABLE_THREAD_ASSERTIONS": "1",
                    "SQLITE_ENABLE_FILE_ASSERTIONS": "1"
                ]

                let launchArguments: [LaunchArgument] = [
                    .init(name: "-com.apple.CoreData.MigrationDebug 1", isEnabled: true),
                    .init(name: "-com.apple.CoreData.SQLDebug 1", isEnabled: false),
                    .init(name: "-com.apple.CoreData.ConcurrencyDebug 1", isEnabled: true)
                ]

                let arguments = Arguments(environment: runEnvironment,
                                          launchArguments: launchArguments)

                let appStoreScheme = Scheme(name: $0.name,
                                               shared: true,
                                               hidden: false,
                                               buildAction: .buildAction(targets: [.init(stringLiteral: $0.name)]),
                                               testAction: .targets([], configuration: .appStoreDebug),
                                               runAction: .runAction(configuration: .appStoreDebug,
                                                                     attachDebugger: true,
                                                                     arguments: arguments,
                                                                     options: runActionOptions,
                                                                     diagnosticsOptions: [
                                                                        .mainThreadChecker
                                                                     ]),
                                               archiveAction: .archiveAction(configuration: .appStoreRelease),
                                               profileAction: .profileAction(configuration: .appStoreRelease),
                                               analyzeAction: .analyzeAction(configuration: .appStoreDebug))

                return [appStoreScheme]

            case .appClip,
                    .appExtension,
                    .bundle,
                    .commandLineTool,
                    .dynamicLibrary,
                    .framework,
                    .messagesExtension,
                    .staticFramework,
                    .staticLibrary,
                    .stickerPackExtension,
                    .tvTopShelfExtension,
                    .uiTests,
                    .unitTests,
                    .watch2App,
                    .watch2Extension,
                    .xpc:
                return []
                
            @unknown default:
                return []
            }
        }
    }
}
