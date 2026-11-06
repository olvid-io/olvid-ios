/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
 *
 *  This file is part of Olvid for iOS.
 *
 *  Olvid is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU Affero General Public License, version 3,
 *  as published by the Free Software Foundation.
 *
 *  Olvid is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU Affero General Public License for more details.
 *
 *  You should have received a copy of the GNU Affero General Public License
 *  along with Olvid.  If not, see <https://www.gnu.org/licenses/>.
 */

import CoreData
import OlvidUtils
import XCTest
@testable import ObvDatabaseManager


/// Checks the delete rules the engine relies on, in the latest model, without a store.
///
/// A delete rule is written in the model and nowhere else, so code deleting a row is correct only as long as the model agrees.
/// Nothing in a build fails when one is changed, and the loss is silent: rows that should have gone stay for ever.
final class ObvEngineModelDeleteRulesTests: XCTestCase {

    private typealias Version = DataMigrationManagerForObvEngine.ObvEngineModelVersion

    private var manager: DataMigrationManagerForObvEngine!

    override func setUpWithError() throws {
        manager = DataMigrationManagerForObvEngine(modelName: "ObvEngine",
                                                   storeName: "ObvEngine",
                                                   transactionAuthor: "ObvEngineModelDeleteRulesTests",
                                                   enableMigrations: true,
                                                   migrationRunningLog: RunningLogError())
    }

    override func tearDown() {
        manager = nil
    }

    private func latestModel() throws -> NSManagedObjectModel {
        let models = try manager.getAllManagedObjectModels()
        let latest = models.filter { model in
            guard model.versionIdentifiers.count == 1, let identifier = model.versionIdentifiers.first as? String else { return false }
            return Version(rawValue: identifier) == .latest
        }
        XCTAssertEqual(latest.count, 1, "Exactly one model is the latest")
        return try XCTUnwrap(latest.first)
    }

    /// A protocol instance waiting for a child holds the link naming that child, and the bootstrap sweep deletes such an instance
    /// when nothing can answer it any more. Only this rule takes the link with it; made to nullify, the sweep would leave a link row
    /// per parent it removed, pointing at nothing and never read again.
    func testALinkBetweenProtocolInstancesIsDeletedWithItsParent() throws {

        let model = try latestModel()

        let protocolInstance = try XCTUnwrap(model.entitiesByName["ProtocolInstance"])
        let link = try XCTUnwrap(protocolInstance.relationshipsByName["linkBetweenProtocolInstance"])

        XCTAssertEqual(link.deleteRule, .cascadeDeleteRule)
        XCTAssertEqual(link.maxCount, 1)

        // The link names its parent and nothing else, so deleting the link must leave the parent alone

        let parent = try XCTUnwrap(link.inverseRelationship)
        XCTAssertEqual(parent.name, "parentProtocolInstance")
        XCTAssertEqual(parent.deleteRule, .nullifyDeleteRule)
        XCTAssertEqual(parent.entity.name, "LinkBetweenProtocolInstances")

    }

}
