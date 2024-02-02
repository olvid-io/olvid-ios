import ProjectDescription
import ProjectDescriptionHelpers


let obvCircledInitials = Target.swiftLibrary(
    name: "UI_ObvCircledInitials",
    isExtensionSafe: true,
    sources: "ObvCircledInitials/*.swift",
    dependencies: [
        .Engine.obvCrypto,
        .Engine.obvTypes,
        .Modules.obvDesignSystem,
        .Modules.obvSettings,
    ]
)

let uiSystemIcon = Target.swiftLibrary(
    name: "UI_SystemIcon",
    isExtensionSafe: true,
    sources: "SystemIcon/*.swift",
    dependencies: [],
    resources: [])

let uiSystemIconSwiftUI = Target.swiftLibrary(
    name: "UI_SystemIcon_SwiftUI",
    isExtensionSafe: true,
    sources: "SystemIcon_SwiftUI/*.swift",
    dependencies: [
        .target(uiSystemIcon)
    ],
    resources: [])

let uiSystemIconUIKit = Target.swiftLibrary(
    name: "UI_SystemIcon_UIKit",
    isExtensionSafe: true,
    sources: "SystemIcon_UIKit/*.swift",
    dependencies: [
        .target(uiSystemIcon)
    ],
    resources: [])

let obvImageEditor = Target.swiftLibrary(
    name: "UI_ObvImageEditor",
    isExtensionSafe: true,
    sources: "ObvImageEditor/Sources/*.swift",
    dependencies: [],
    resources: [])


let obvPhotoButton = Target.swiftLibrary(
    name: "UI_ObvPhotoButton",
    isExtensionSafe: true,
    sources: "ObvPhotoButton/*.swift",
    dependencies: [
        .target(obvCircledInitials),
        .target(uiSystemIconSwiftUI),
    ],
    resources: [
        "ObvPhotoButton/*.xcstrings",
    ]
)


let project = Project.createProject(
    name: "UI",
    packages: [],
    targets: [
        uiSystemIcon,
        uiSystemIconSwiftUI,
        uiSystemIconUIKit,
        obvCircledInitials,
        obvPhotoButton,
        obvImageEditor,
    ])
