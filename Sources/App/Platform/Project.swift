import ProjectDescription
import ProjectDescriptionHelpers

let platformBase = Target.makeSwiftLibraryTarget(
    name: "ObvPlatformBase",
    sources: "Base/*.swift",
    resources: nil,
    dependencies: [],
    isExtensionSafe: true)

let uiKitAdditions = Target.makeSwiftLibraryTarget(
    name: "ObvPlatformUIKitAdditions",
    sources: "UIKit_Additions/*.swift",
    resources: nil,
    dependencies: [],
    isExtensionSafe: true)

let sequenceKeyPathSorting = Target.makeSwiftLibraryTarget(
    name: "ObvPlatformSequenceKeyPathSorting",
    sources: "Sequence_KeyPathSorting/*.swift",
    resources: nil,
    dependencies: [],
    isExtensionSafe: true)

let nsItemProviderUTTypeBackport = Target.makeSwiftLibraryTarget(
    name: "ObvPlatformNSItemProviderUTTypeBackport",
    sources: "NSItemProvider_UTType_Backport/*.swift",
    resources: nil,
    dependencies: [],
    isExtensionSafe: true)

let project = Project.createProjectForFrameworkLegacy(
    name: "Platform",
    packages: [],
    targets: [
        platformBase,
        uiKitAdditions,
        sequenceKeyPathSorting,
        nsItemProviderUTTypeBackport,
    ])
