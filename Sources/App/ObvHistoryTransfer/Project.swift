import ProjectDescription
import ProjectDescriptionHelpers


let name = "ObvHistoryTransfer"


// MARK: - Targets

private let frameworkTarget = Target.makeFrameworkTarget(
    name: name,
    resources: [
        "Resources/StaticFilesToIncludeInZip/app.js",
        "Resources/StaticFilesToIncludeInZip/index.html",
        "Resources/StaticFilesToIncludeInZip/template.html",
        "Resources/StaticFilesToIncludeInZip/viewer.css",
        "Resources/Localizable.xcstrings",
    ],
    developmentAssets: "DevelopmentResources",
    dependencies: [
        .Olvid.App.obvSystemIcon,
        .Olvid.App.obvDesignSystem,
        .Olvid.App.obvAppCoreConstants,
        .Olvid.App.obvAppTypes,
        .Olvid.App.obvContinuedProcessingTaskManager,
        .Olvid.Shared.obvOwnedIdentityChooser,
        .Olvid.Shared.obvTypes,
        .Olvid.Engine.obvCrypto,
        .xcframework(path: .relativeToRoot("ExternalDependencies/XCFrameworks/WebRTC.xcframework")),
        .package(product: "ZipArchive"),
        .Olvid.App.ThirdParty.confettiSwiftUI,
    ],
    enableSwift6: true)

private let frameworkTestsTarget = Target.makeFrameworkUnitTestsTarget(
    forTesting: frameworkTarget)

// MARK: - Project

let project = Project.createProjectForFramework(
    packages: [
        .remote(url: "https://github.com/ZipArchive/ZipArchive", requirement: .exact(.init(2, 6, 0))),
    ],
    frameworkTarget: frameworkTarget,
    frameworkTestsTarget: frameworkTestsTarget)
