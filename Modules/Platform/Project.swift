import ProjectDescription
import ProjectDescriptionHelpers

let platformBase = Target.swiftLibrary(
    name: "Platform_Base",
    isExtensionSafe: true,
    sources: "Base/*.swift",
    dependencies: [],
    resources: [])

let uiKitAdditions = Target.swiftLibrary(
    name: "Platform_UIKit_Additions",
    isExtensionSafe: true,
    sources: "UIKit_Additions/*.swift",
    dependencies: [],
    resources: [])

let sequenceKeyPathSorting = Target.swiftLibrary(
    name: "Platform_Sequence_KeyPathSorting",
    isExtensionSafe: true,
    sources: "Sequence_KeyPathSorting/*.swift",
    dependencies: [],
    resources: [])

let nsItemProviderUTTypeBackport = Target.swiftLibrary(
    name: "Platform_NSItemProvider_UTType_Backport",
    isExtensionSafe: true,
    sources: "NSItemProvider_UTType_Backport/*.swift",
    dependencies: [],
    resources: []
)

let project = Project.createProject(
    name: "Platform",
    packages: [],
    targets: [platformBase,
              uiKitAdditions,
              sequenceKeyPathSorting,
              nsItemProviderUTTypeBackport])
