import ProjectDescription
import ProjectDescriptionHelpers

let name = "ObvCoreDataStack"


// MARK: - Targets

private let frameworkTarget = Target.makeFrameworkTarget(
    name: name,
    dependencies: [
        .Olvid.Shared.olvidUtils,
    ])

// Note: we cannot activate the prepareForSwift6: this generates warnings for the notification sent in DataMigrationManagerNotification.
// We will need to find a fix for sending notifications.

// MARK: - Project

let project = Project.createProjectForFramework(
    frameworkTarget: frameworkTarget,
    frameworkTestsTarget: nil)
