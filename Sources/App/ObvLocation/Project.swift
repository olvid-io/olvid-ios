import ProjectDescription
import ProjectDescriptionHelpers


let name = "ObvLocation"


// MARK: - Targets

private let frameworkTarget = Target.makeFrameworkTarget(
    name: name,
    resources: [
        "Resources/Localizable.xcstrings",
    ],
    dependencies: [
        .Olvid.App.obvSettings,
        .Olvid.App.obvUICoreData,
        .Olvid.App.obvUI,
        .Olvid.App.obvAppTypes,
        .Olvid.App.obvAppCoreConstants,
        .Olvid.Shared.obvTypes,
    ],
    enableSwift6: true)


// MARK: - Project

let project = Project.createProjectForFramework(
    frameworkTarget: frameworkTarget,
    frameworkTestsTarget: nil)
