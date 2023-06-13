import ProjectDescription
import ProjectDescriptionHelpers

let textInputShortcutsResultView = Target.swiftLibrary(
    name: "Components_TextInputShortcutsResultView",
    isExtensionSafe: true,
    sources: [
        "TextInputShortcutsResultView/*.swift"
    ],
    dependencies: [
        .Modules.Platform.base,
        .Modules.obvUI,
        .Modules.UI.CircledInitialsView.configuration,
    ]
)

let project = Project.createProject(name: "TextInputShortcutsResultView",
                                    packages: [],
                                    targets: [textInputShortcutsResultView])
