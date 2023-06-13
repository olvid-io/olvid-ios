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
                                            .Modules.UI.CircledInitialsView.configuration,
                                        ],
                                        resources: [
                                            "OlvidUI/ObvUICoreData/ObvUICoreData/*.lproj/*.strings",
                                            "OlvidUI/ObvUICoreData/ObvUICoreData/*.lproj/*.stringsdict",
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
                                    .sdk(name: "SwiftUI", type: .framework),
                                    .sdk(name: "UIKit", type: .framework),
                                    .sdk(name: "UniformTypeIdentifiers", type: .framework, status: .optional)
                                ],
                                resources: [
                                    "OlvidUI/ObvUI/ObvUI/*.lproj/*.strings",
                                    "OlvidUI/ObvUI/ObvUI/ObvUIAssets.xcassets"
                                ])


let coreDataStack = Target.swiftLibrary(name: "CoreDataStack",
                                        isExtensionSafe: true,
                                        sources: "CoreDataStack/CoreDataStack/*.swift",
                                        dependencies: [
                                            .target(olvidUtils)
                                        ],
                                        resources: [])

let project = Project.createProject(name: "Modules",
                                    packages: [],
                                    targets: [obvUICoreData,
                                              obvUI,
                                              olvidUtils,
                                              coreDataStack])
