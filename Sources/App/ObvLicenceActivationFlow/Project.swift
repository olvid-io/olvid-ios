import ProjectDescription
import ProjectDescriptionHelpers


let name = "ObvLicenceActivationFlow"


// MARK: - Targets

private let frameworkTarget = Target.makeFrameworkTarget(
    name: name,
    resources: [
        "Resources/Localizable.xcstrings",
    ],
    dependencies: [
        .Olvid.App.obvDesignSystem,
        .Olvid.App.obvSystemIcon,
        .Olvid.App.obvAppCoreConstants,
        .Olvid.Shared.obvTypes,
        .Olvid.App.ThirdParty.confettiSwiftUI
    ],
    enableSwift6: true)


// MARK: - Project

let project = Project.createProjectForFramework(
    frameworkTarget: frameworkTarget,
    frameworkTestsTarget: nil)
