import ProjectDescription
import ProjectDescriptionHelpers

let name = "ObvEngine"


// MARK: - Targets

private let frameworkTarget = Target.makeFrameworkTarget(
    name: name,
    dependencies: [
        .Olvid.Engine.obvJWS,
        .Olvid.Engine.obvBackupManager,
        .Olvid.Engine.obvBackupManagerNew,
        .Olvid.Engine.obvChannelManager,
        .Olvid.Engine.obvCrypto,
        .Olvid.Engine.obvDatabaseManager,
        .Olvid.Engine.obvEncoder,
        .Olvid.Engine.obvFlowManager,
        .Olvid.Engine.obvIdentityManager,
        .Olvid.Engine.obvMetaManager,
        .Olvid.Engine.obvNotificationCenter,
        .Olvid.Engine.obvProtocolManager,
        .Olvid.Engine.obvServerInterface,
        .Olvid.Engine.obvSyncSnapshotManager,
        .Olvid.Engine.obvNetworkSendManager,
        .Olvid.Engine.obvNetworkFetchManager,
        .Olvid.Shared.obvTypes,
        .Olvid.Shared.olvidUtils,
    ])


// MARK: - Project

let project = Project.createProjectForFramework(
    frameworkTarget: frameworkTarget,
    frameworkTestsTarget: nil)
