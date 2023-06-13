import ProjectDescription
import ProjectDescriptionHelpers

let workspace = Workspace.createWorkspace(name: "Olvid",
                                          projects: [
                                            "iOSClient/ObvMessenger",
                                            "Engine/",
                                            "Modules/"
                                          ])
