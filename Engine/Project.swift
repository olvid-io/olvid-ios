import ProjectDescription
import ProjectDescriptionHelpers

// MARK: SPM Packages
let gmpPackage = TargetDependency.SPMDependency.gmp
let joseSwiftSPM = TargetDependency.SPMDependency.joseSwift
// MARK: -

// MARK: External Targets
let coreDataStack: TargetDependency = .Modules.coreDataStack
let olvidUtils: TargetDependency = .Modules.olvidUtils
// MARK: -

// MARK: BigInt
let bigInt = Target.swiftLibrary(name: "BigInt",
                                 isExtensionSafe: true,
                                 sources: "BigInt/BigInt/BigInt/*.swift",
                                 dependencies: [
                                    .init(gmpPackage)
                                 ],
                                 resources: [])

let bigIntTests = Target.swiftLibraryTests(name: "BigIntTests",
                                           sources: "BigInt/BigInt/BigIntTests/*.swift",
                                           dependencies: [
                                            .target(name: bigInt.name)
                                           ],
                                           resources: [])
// MARK: -

// MARK: JWS
let jws = Target.swiftLibrary(name: "JWS",
                              isExtensionSafe: true,
                              sources: "JWS/JWS/*.swift",
                              dependencies: [
                                .init(joseSwiftSPM)
                              ],
                              resources: [])
// MARK: -

// MARK: ObvBackupManager
let obvBackupManager = Target.swiftLibrary(name: "ObvBackupManager",
                                           isExtensionSafe: true,
                                           sources: "ObvBackupManager/ObvBackupManager/**/*.swift",
                                           dependencies: [
                                            .target(name: "ObvMetaManager"),
                                           ],
                                           resources: [])
// MARK: -

// MARK: ObvChannelManager
let obvChannelManager = Target.swiftLibrary(name: "ObvChannelManager",
                                            isExtensionSafe: true,
                                            sources: "ObvChannelManager/ObvChannelManager/**/*.swift",
                                            dependencies: [
                                                .target(name: "ObvTypes"),
                                                .target(name: "ObvCrypto"),
                                                .target(name: "ObvMetaManager"),
                                                olvidUtils
                                            ],
                                            resources: [])
// MARK: -

// MARK: ObvCrypto
let obvCrypto = Target.swiftLibrary(name: "ObvCrypto",
                                    isExtensionSafe: true,
                                    sources: "ObvCrypto/ObvCrypto/**/*.swift",
                                    dependencies: [
                                        .target(name: bigInt.name),
                                        .target(name: "ObvEncoder"),
                                        olvidUtils,
                                    ],
                                    resources: [])
// MARK: -

// MARK: ObvDatabaseManager
let obvDatabaseManager = Target.swiftLibrary(name: "ObvDatabaseManager",
                                             isExtensionSafe: true,
                                             sources: [
                                                "ObvDatabaseManager/ObvDatabaseManager/**/*.swift",
                                                "ObvDatabaseManager/ObvDatabaseManager/**/*.xcmappingmodel",
                                             ],
                                             dependencies: [
                                                .target(name: "ObvTypes"),
                                                .target(name: "ObvMetaManager"),
                                                coreDataStack
                                             ],
                                             resources: [],
                                             coreDataModels: [
                                                .init("ObvDatabaseManager/ObvDatabaseManager/ObvEngine.xcdatamodeld", currentVersion: nil)
                                             ],
                                             additionalFiles: [
                                                "ObvDatabaseManager/ObvDatabaseManager/Migration/**/*.md",
                                                "ObvDatabaseManager/ObvDatabaseManager/Migration/**/*.txt",
                                             ])
// MARK: -

// MARK: ObvEncoder
let obvEncoder = Target.swiftLibrary(name: "ObvEncoder",
                                     isExtensionSafe: true,
                                     sources: "ObvEncoder/ObvEncoder/**/*.swift",
                                     dependencies: [
                                        .target(name: bigInt.name),
                                     ],
                                     resources: [])
// MARK: -

// MARK: ObvEngine
let obvEngine = Target.swiftLibrary(name: "ObvEngine",
                                    isExtensionSafe: true,
                                    sources: "ObvEngine/ObvEngine/**/*.swift",
                                    dependencies: [
                                        .target(name: "ObvDatabaseManager"),
                                        .target(name: "ObvFlowManager"),
                                        .target(name: "JWS"),
                                        .target(name: "ObvCrypto"),
                                        .target(name: "ObvProtocolManager"),
                                        .target(name: "ObvNotificationCenter"),
                                        .target(name: "ObvNetworkSendManager"),
                                        .target(name: "ObvNetworkFetchManager"),
                                        olvidUtils,
                                        .target(name: "ObvMetaManager"),
                                        .target(name: "ObvIdentityManager"),
                                        .target(name: "ObvBackupManager"),
                                        .target(name: "ObvChannelManager"),
                                    ],
                                    resources: [],
                                    additionalFiles: [
                                        "ObvEngine/ObvEngine/*.yml"
                                    ])
// MARK: -

// MARK: ObvFlowManager
let obvFlowManager = Target.swiftLibrary(name: "ObvFlowManager",
                                         isExtensionSafe: true,
                                         sources: "ObvFlowManager/ObvFlowManager/**/*.swift",
                                         dependencies: [
                                            .target(name: "ObvNotificationCenter"),
                                            .target(name: "ObvMetaManager"),
                                         ],
                                         resources: [])
// MARK: -

// MARK: ObvIdentityManager
let obvIdentityManager = Target.swiftLibrary(name: "ObvIdentityManager",
                                             isExtensionSafe: true,
                                             sources: "ObvIdentityManager/ObvIdentityManager/**/*.swift",
                                             dependencies: [
                                                .target(name: "ObvMetaManager"),
                                                olvidUtils,
                                                .target(name: "ObvCrypto"),
                                                .target(name: "JWS"),
                                                .target(name: "ObvTypes"),
                                             ],
                                             resources: [])
// MARK: -

// MARK: ObvMetaManager
let obvMetaManager = Target.swiftLibrary(name: "ObvMetaManager",
                                         isExtensionSafe: true,
                                         sources: "ObvMetaManager/ObvMetaManager/**/*.swift",
                                         dependencies: [
                                            .target(name: "ObvTypes"),
                                            .target(name: "ObvCrypto"),
                                            .target(name: "JWS"),
                                            .target(name: "ObvEncoder"),
                                         ],
                                         resources: [])
// MARK: -

// MARK: ObvNetworkFetchManager
let obvNetworkFetchManager = Target.swiftLibrary(name: "ObvNetworkFetchManager",
                                                 isExtensionSafe: true,
                                                 sources: "ObvNetworkFetchManager/ObvNetworkFetchManager/**/*.swift",
                                                 dependencies: [
                                                    .target(name: "ObvOperation"),
                                                    .target(name: "JWS"),
                                                    olvidUtils,
                                                    .target(name: "ObvServerInterface"),
                                                    .target(name: "ObvMetaManager"),
                                                    .target(name: "ObvTypes")
                                                 ],
                                                 resources: [])
// MARK: -

// MARK: ObvNetworkSendManager
let obvNetworkSendManager = Target.swiftLibrary(name: "ObvNetworkSendManager",
                                                isExtensionSafe: true,
                                                sources: "ObvNetworkSendManager/ObvNetworkSendManager/**/*.swift",
                                                dependencies: [
                                                    .target(name: "ObvMetaManager"),
                                                    olvidUtils,
                                                    .target(name: "ObvOperation"),
                                                    .target(name: "ObvServerInterface"),
                                                    .target(name: "ObvCrypto")
                                                ],
                                                resources: [])
// MARK: -

// MARK: ObvNotificationCenter
let obvNotificationCenter = Target.swiftLibrary(name: "ObvNotificationCenter",
                                                isExtensionSafe: true,
                                                sources: "ObvNotificationCenter/ObvNotificationCenter/**/*.swift",
                                                dependencies: [
                                                    .target(name: "ObvMetaManager"),
                                                ],
                                                resources: [])
// MARK: -

// MARK: ObvOperation
let obvOperation = Target.swiftLibrary(name: "ObvOperation",
                                       isExtensionSafe: true,
                                       sources: "ObvOperation/ObvOperation/**/*.swift",
                                       dependencies: [
                                        .target(name: "ObvTypes")
                                       ],
                                       resources: [])
// MARK: -

// MARK: ObvProtocolManager
let obvProtocolManager = Target.swiftLibrary(name: "ObvProtocolManager",
                                             isExtensionSafe: true,
                                             sources: "ObvProtocolManager/ObvProtocolManager/**/*.swift",
                                             dependencies: [
                                                .target(name: "ObvOperation"),
                                                .target(name: "JWS"),
                                                .target(name: "ObvMetaManager"),
                                                olvidUtils
                                             ],
                                             resources: [])
// MARK: -

// MARK: ObvServerInterface
let obvServerInterface = Target.swiftLibrary(name: "ObvServerInterface",
                                             isExtensionSafe: true,
                                             sources: "ObvServerInterface/ObvServerInterface/**/*.swift",
                                             dependencies: [
                                                .target(name: "ObvTypes"),
                                                olvidUtils,
                                                .target(name: "ObvMetaManager"),
                                                .target(name: "ObvEncoder"),
                                                .target(name: "ObvCrypto")
                                             ],
                                             resources: [])
// MARK: -

// MARK: ObvTypes
let obvTypes = Target.swiftLibrary(name: "ObvTypes",
                                   isExtensionSafe: true,
                                   sources: "ObvTypes/ObvTypes/**/*.swift",
                                   dependencies: [
                                    .target(name: "JWS"),
                                    olvidUtils,
                                    .target(name: "ObvCrypto"),
                                    .target(name: "ObvEncoder"),
                                   ],
                                   resources: [])

let obvTypesTests = Target.swiftLibraryTests(name: "ObvTypesTests",
                                             sources: "ObvTypes/ObvTypesTests/**/*.swift",
                                             dependencies: [
                                                .target(name: "ObvTypes"),
                                                .xctest
                                             ],
                                             resources: [])

// MARK: -

let project = Project.createProject(name: "Engine",
                                    packages: [],
                                    targets: [bigInt,
                                              bigIntTests,
                                              jws,
                                              obvBackupManager,
                                              obvChannelManager,
                                              obvCrypto,
                                              obvDatabaseManager,
                                              obvEncoder,
                                              obvEngine,
                                              obvFlowManager,
                                              obvIdentityManager,
                                              obvMetaManager,
                                              obvNetworkFetchManager,
                                              obvNetworkSendManager,
                                              obvNotificationCenter,
                                              obvOperation,
                                              obvProtocolManager,
                                              obvServerInterface,
                                              obvTypes,
                                              obvTypesTests])
