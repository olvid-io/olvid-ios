import ProjectDescription
import ProjectDescriptionHelpers

let textInputShortcutsResultView = Target.makeSwiftLibraryTarget(
    name: "ObvComponentsTextInputShortcutsResultView",
    sources: [
        "TextInputShortcutsResultView/*.swift"
    ],
    resources: nil,
    dependencies: [
        .Olvid.App.Platform.base,
        .Olvid.App.obvUI,
        .Olvid.App.UI.obvCircledInitials,
    ],
    isExtensionSafe: true)

let project = Project.createProjectForFrameworkLegacy(name: "TextInputShortcutsResultView", targets: [textInputShortcutsResultView])
