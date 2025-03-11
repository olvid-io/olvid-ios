import ProjectDescription
import ProjectDescriptionHelpers


let name = "ObvTypes"


// MARK: - Targets

private let frameworkTarget = Target.makeFrameworkTarget(
    name: name,
    dependencies: [
        .Olvid.Engine.obvJWS,
        .Olvid.Engine.obvCrypto,
        .Olvid.Engine.obvEncoder,
        .Olvid.Shared.olvidUtils,
    ],
    prepareForSwift6: true)

private let frameworkTestsTarget = Target.makeFrameworkUnitTestsTarget(
    forTesting: frameworkTarget)


// MARK: - Project

let project = Project.createProjectForFramework(
    frameworkTarget: frameworkTarget,
    frameworkTestsTarget: frameworkTestsTarget)
