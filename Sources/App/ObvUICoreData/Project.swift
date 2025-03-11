import ProjectDescription
import ProjectDescriptionHelpers


let name = "ObvUICoreData"


// MARK: - Targets

private let frameworkTarget = Target.makeFrameworkTarget(
    name: name,
    resources: [
        "Resources/Localizable.xcstrings",
    ],
    dependencies: [
        .Olvid.Engine.obvCrypto,
        .Olvid.Engine.obvEncoder,
        .Olvid.Engine.obvEngine,
        .Olvid.Shared.obvTypes,
        .Olvid.Shared.olvidUtils,
        .Olvid.App.UI.obvCircledInitials,
        .Olvid.App.ObvUserNotifications.sounds,
        .Olvid.App.Platform.base,
        .Olvid.App.obvDesignSystem,
        .Olvid.App.obvSettings,
        .Olvid.App.obvAppDatabase,
        .Olvid.App.obvUICoreDataStructs,
        .Olvid.App.obvAppTypes,
    ])


// MARK: - Project

let project = Project.createProjectForFramework(
    frameworkTarget: frameworkTarget,
    frameworkTestsTarget: nil)
