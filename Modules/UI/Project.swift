import ProjectDescription
import ProjectDescriptionHelpers


let circledInitialsViewConfiguration = Target.swiftLibrary(
    name: "UI_CircledInitialsView_CircledInitialsConfiguration",
    isExtensionSafe: true,
        sources: "CircledInitialsView/CircledInitialsConfiguration/*.swift",
    dependencies: [
        .Engine.obvCrypto,
        .Engine.obvTypes,
    ]
)

let uiSystemIcon = Target.swiftLibrary(name: "UI_SystemIcon",
                                       isExtensionSafe: true,
                                       sources: "SystemIcon/*.swift",
                                       dependencies: [],
                                       resources: [])

let uiSystemIconSwiftUI = Target.swiftLibrary(name: "UI_SystemIcon_SwiftUI",
                                              isExtensionSafe: true,
                                              sources: "SystemIcon_SwiftUI/*.swift",
                                              dependencies: [
                                                .target(uiSystemIcon)
                                              ],
                                              resources: [])

let uiSystemIconUIKit = Target.swiftLibrary(name: "UI_SystemIcon_UIKit",
                                            isExtensionSafe: true,
                                            sources: "SystemIcon_UIKit/*.swift",
                                            dependencies: [
                                                .target(uiSystemIcon)
                                            ],
                                            resources: [])

let project = Project.createProject(name: "UI",
                                    packages: [],
                                    targets: [uiSystemIcon,
                                              uiSystemIconSwiftUI,
                                              uiSystemIconUIKit,
					      circledInitialsViewConfiguration])
