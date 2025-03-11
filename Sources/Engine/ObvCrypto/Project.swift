import ProjectDescription
import ProjectDescriptionHelpers


let name = "ObvCrypto"


// MARK: - Targets

private let frameworkTarget = Target.makeFrameworkTarget(
    name: name,
    dependencies: [
        .Olvid.Engine.obvBigInt,
        .Olvid.Shared.olvidUtils,
        .Olvid.Engine.obvEncoder,
    ])

private let frameworkTestsTarget = Target.makeFrameworkUnitTestsTarget(
    forTesting: frameworkTarget,
    resources: [
        "Tests/TestVectors/*",
    ])


// MARK: - Project

let project = Project.createProjectForFramework(
    frameworkTarget: frameworkTarget,
    frameworkTestsTarget: frameworkTestsTarget)
