import ProjectDescription
import ProjectDescriptionHelpers


let name = "ConfettiSwiftUI"


// MARK: - Targets

private let frameworkTarget = Target.makeFrameworkTarget(
    name: name,
    resources: [],
    dependencies: [],
    enableSwift6: true)

// MARK: - Project

let project = Project.createProjectForFramework(
    frameworkTarget: frameworkTarget,
    frameworkTestsTarget: nil)
