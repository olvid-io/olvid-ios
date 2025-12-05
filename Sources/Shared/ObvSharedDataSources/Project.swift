import ProjectDescription
import ProjectDescriptionHelpers


let name = "ObvSharedDataSources"


// MARK: - Targets

private let frameworkTarget = Target.makeFrameworkTarget(
    name: name,
    resources: [],
    dependencies: [
        .Olvid.App.obvAppCoreConstants,
        .Olvid.App.obvUICoreData,
        .Olvid.App.obvDesignSystem,
        .Olvid.Shared.obvTypes,
        .Olvid.Shared.obvOwnedIdentityChooser,
        .Olvid.Shared.olvidUtils,
    ],
    enableSwift6: true)


// MARK: - Project

let project = Project.createProjectForFramework(
    frameworkTarget: frameworkTarget,
    frameworkTestsTarget: nil)
