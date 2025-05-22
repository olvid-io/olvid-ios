import ProjectDescription
import ProjectDescriptionHelpers

let obvImageEditor = Target.makeSwiftLibraryTarget(
    name: "ObvImageEditor",
    sources: "ObvImageEditor/Sources/*.swift",
    resources: nil,
    dependencies: [],
    isExtensionSafe: true)

let obvCircledInitials = Target.makeSwiftLibraryTarget(
    name: "ObvUIObvCircledInitials",
    sources: "ObvCircledInitials/*.swift",
    resources: nil,
    dependencies: [
        .Olvid.Engine.obvCrypto,
        .Olvid.App.obvDesignSystem,
        .Olvid.App.obvSettings,
        .Olvid.App.obvSystemIcon,
        .Olvid.Shared.obvTypes,
    ],
    isExtensionSafe: true)

let obvPhotoButton = Target.makeSwiftLibraryTarget(
    name: "ObvUIObvPhotoButton",
    sources: "ObvPhotoButton/*.swift",
    resources: [
        "ObvPhotoButton/*.xcstrings",
    ],
    dependencies: [
        .Olvid.App.obvSystemIcon,
        .target(obvCircledInitials),
    ],
    isExtensionSafe: true)

let obvScannerHostingView = Target.makeSwiftLibraryTarget(
    name: "ObvScannerHostingView",
    sources: "ObvScannerHostingView/Sources/*.swift",
    resources: [
        "ObvScannerHostingView/Resources/Localizable.xcstrings",
    ],
    dependencies: [
        .Olvid.App.obvDesignSystem,
        .Olvid.App.obvAppCoreConstants,
        .Olvid.App.obvAppTypes,
        .Olvid.App.obvUI,
    ],
    isExtensionSafe: true)


let obvCircleAndTitlesView = Target.makeFrameworkTarget(
    name: "ObvCircleAndTitlesView",
    sourcesDirectoryName: "ObvCircleAndTitlesView",
    resources: [
        "ObvCircleAndTitlesView/Resources/Localizable.xcstrings",
    ],
    dependencies: [
        .Olvid.App.UI.obvCircledInitials,
        .Olvid.App.UI.obvImageEditor,
        .Olvid.App.obvDesignSystem,
        .Olvid.App.obvSystemIcon,
        .Olvid.App.obvAppCoreConstants,
    ],
    enableSwift6: true)

let project = Project.createProjectForFrameworkLegacy(
    name: "UI",
    packages: [],
    targets: [
        obvCircledInitials,
        obvPhotoButton,
        obvImageEditor,
        obvScannerHostingView,
        obvCircleAndTitlesView,
    ])
