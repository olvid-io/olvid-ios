import ProjectDescription
import ProjectDescriptionHelpers

let workspace = Workspace.createWorkspace(
    name: "Olvid", 
    projects: [
        .olvidPath("AppAndExtensions", in: .app),
    ])
