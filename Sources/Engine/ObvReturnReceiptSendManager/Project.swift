import ProjectDescription
import ProjectDescriptionHelpers


let name = "ObvReturnReceiptSendManager"


// MARK: - Targets

private let frameworkTarget = Target.makeFrameworkTarget(
    name: name,
    dependencies: [
        .Olvid.Engine.obvCrypto,
        .Olvid.Engine.obvServerInterface,   // ObvServerUploadReturnReceipt
        .Olvid.Engine.obvEncoder,
        .Olvid.Engine.obvMetaManager,       // AppType
        .Olvid.Shared.olvidUtils,
        .Olvid.Shared.obvCoreDataStack,
        .Olvid.Shared.obvTypes,
    ],
    coreDataModels: [.olvidCoreDataModel(.returnReceiptSend)])

private let frameworkTestsTarget = Target.makeFrameworkUnitTestsTarget(
    forTesting: frameworkTarget)


// MARK: - Project

let project = Project.createProjectForFramework(
    frameworkTarget: frameworkTarget,
    frameworkTestsTarget: frameworkTestsTarget)
