import ProjectDescription
import ProjectDescriptionHelpers


// We use the "Xcode's default integration" way for including the AppAuth package.
// See https://docs.tuist.io/guides/develop/projects/dependencies#external-dependencies

let name = "ObvOnboarding"


// MARK: - Targets

private let frameworkTarget = Target.makeFrameworkTarget(
    name: name,
    resources: [
        "Resources/Localizable.xcstrings",
        "Resources/ObvOnboardingAssets.xcassets",
    ],
    dependencies: [
        .package(product: "AppAuth"),
        .Olvid.App.obvAppCoreConstants,
        .Olvid.App.obvKeycloakManager,
        .Olvid.App.obvSettings,
        .Olvid.App.obvSystemIcon,
        .Olvid.App.obvSubscription,
        .Olvid.App.obvAppTypes,
        .Olvid.App.UI.obvImageEditor,
        .Olvid.App.UI.obvScannerHostingView,
        .Olvid.App.UI.obvCircledInitials,
        .Olvid.App.UI.obvPhotoButton,
        .Olvid.Shared.obvTypes,
        .Olvid.Engine.obvJWS,
        .Olvid.Engine.obvCrypto,
    ])


// MARK: - Project

let project = Project.createProjectForFramework(
    frameworkTarget: frameworkTarget,
    frameworkTestsTarget: nil)
