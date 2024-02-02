import ProjectDescription
import ProjectDescriptionHelpers

let olvidUtils = Target.swiftLibrary(name: "OlvidUtils",
                                     isExtensionSafe: true,
                                     sources: "OlvidUtils/OlvidUtils/**/*.swift",
                                     dependencies: [],
                                     resources: [])

let obvUICoreData = Target.swiftLibrary(name: "ObvUICoreData",
                                        isExtensionSafe: true,
                                        sources: "OlvidUI/ObvUICoreData/ObvUICoreData/**/*.swift",
                                        dependencies: [
                                            .sdk(name: "CoreData", type: .framework),
                                            .sdk(name: "CoreServices", type: .framework),
                                            .sdk(name: "MobileCoreServices", type: .framework),
                                            .sdk(name: "UniformTypeIdentifiers", type: .framework),
                                            .Engine.obvEngine,
                                            .target(olvidUtils),
                                            .sdk(name: "UniformTypeIdentifiers", type: .framework, status: .optional),
                                            .Modules.UI.obvCircledInitials,
                                            .Modules.obvSettings,
                                            //.Modules.UI.CircledInitialsView.configuration,
                                        ],
                                        resources: [
                                            "OlvidUI/ObvUICoreData/ObvUICoreData/*.xcstrings",
                                        ])

let obvUI = Target.swiftLibrary(name: "ObvUI",
                                isExtensionSafe: true,
                                sources: "OlvidUI/ObvUI/ObvUI/**/*.swift",
                                dependencies: [
                                    .target(obvUICoreData),
                                    .target(name: "OlvidUtils"),
                                    .Engine.obvTypes,
                                    .Modules.UI.systemIcon,
                                    .Modules.UI.systemIconSwiftUI,
                                    .Modules.UI.systemIconUIKit,
                                    .Modules.UI.obvImageEditor,
                                    .Modules.UI.obvPhotoButton,
                                    .sdk(name: "SwiftUI", type: .framework),
                                    .sdk(name: "UIKit", type: .framework),
                                    .sdk(name: "UniformTypeIdentifiers", type: .framework, status: .optional)
                                ],
                                resources: [
                                    "OlvidUI/ObvUI/ObvUI/*.xcstrings",
                                ])


let coreDataStack = Target.swiftLibrary(
    name: "CoreDataStack",
    isExtensionSafe: true,
    sources: "CoreDataStack/CoreDataStack/*.swift",
    dependencies: [
        .target(olvidUtils)
    ],
    resources: [])


let obvDesignSystem = Target.swiftLibrary(
    name: "ObvDesignSystem",
    isExtensionSafe: true,
    sources: "ObvDesignSystem/**/*.swift",
    dependencies: [
        .Engine.obvTypes,
        .Engine.obvCrypto,
        .Modules.UI.systemIcon,
        .Modules.UI.systemIconUIKit,
    ],
    resources: [
        "ObvDesignSystem/ObvDesignSystem/AppTheme/AppThemeAssets.xcassets",
    ])


let obvSettings = Target.swiftLibrary(
    name: "ObvSettings",
    isExtensionSafe: true,
    sources: "ObvSettings/**/*.swift",
    dependencies: [
        .Engine.obvTypes,
        .Modules.obvDesignSystem,
    ],
    resources: [
        "ObvSettings/*.xcstrings",
    ])


let project = Project.createProject(
    name: "Modules",
    packages: [],
    targets: [
        obvUICoreData,
        obvUI,
        olvidUtils,
        coreDataStack,
        obvDesignSystem,
        obvSettings,
    ],
    shouldEnableDefaultResourceSynthesizers: true)
