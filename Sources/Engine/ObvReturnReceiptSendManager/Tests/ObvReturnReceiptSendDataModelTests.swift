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
import XCTest
@testable import ObvReturnReceiptSendManager


/// Checks the shape of the v1 model. There is no entity class and no store yet, so these read the compiled `momd`
/// directly. They exist because a mistake in the model is otherwise only found much later, by a store that opens
/// and quietly does the wrong thing.
final class ObvReturnReceiptSendDataModelTests: XCTestCase {

    private static let entityName = "PersistedReturnReceiptToSend"

    private func loadModel() throws -> NSManagedObjectModel {
        let url = try XCTUnwrap(Bundle.module.url(forResource: ObvReturnReceiptSendManagerConstant.coreDataModelName,
                                                  withExtension: "momd"),
                                "The compiled model is not in the framework bundle")
        return try XCTUnwrap(NSManagedObjectModel(contentsOf: url))
    }

    private func loadEntity() throws -> NSEntityDescription {
        let model = try loadModel()
        return try XCTUnwrap(model.entitiesByName[Self.entityName])
    }

    func testTheEntityHasExactlyTheEightAttributesOfTheDesign() throws {
        let entity = try loadEntity()
        let expected: [String: NSAttributeType] = [
            "ownedIdentity": .binaryDataAttributeType,
            "contactIdentity": .binaryDataAttributeType,
            "nonce": .binaryDataAttributeType,
            "key": .binaryDataAttributeType,
            "rawStatus": .integer16AttributeType,
            "rawAttachmentNumber": .integer32AttributeType,
            "serverURL": .URIAttributeType,
            "createdAt": .dateAttributeType,
        ]
        XCTAssertEqual(Set(entity.attributesByName.keys), Set(expected.keys))
        for (name, type) in expected {
            XCTAssertEqual(entity.attributesByName[name]?.attributeType, type, "Wrong type for \(name)")
        }
        XCTAssertTrue(entity.relationshipsByName.isEmpty)
    }

    func testTheUniquenessConstraintIsTheFiveColumnKey() throws {
        let entity = try loadEntity()
        let constraints = entity.uniquenessConstraints.map { constraint in
            Set(constraint.compactMap { ($0 as? String) ?? ($0 as? NSAttributeDescription)?.name })
        }
        XCTAssertEqual(constraints, [["ownedIdentity", "contactIdentity", "nonce", "rawStatus", "rawAttachmentNumber"]])
    }

    /// The constraint is the cross-process dedup, and SQLite considers two NULLs distinct — so an optional column in
    /// it silently switches the dedup off for the rows whose value is nil. Measured: with the attachment number
    /// optional, two coordinators inserting the same message receipt (attachment number nil, which is most rows)
    /// produce two rows, not one. Hence the sentinel carried by `rawAttachmentNumber`.
    func testEveryColumnOfTheUniquenessConstraintIsNonOptional() throws {
        let entity = try loadEntity()
        for constraint in entity.uniquenessConstraints {
            for column in constraint {
                let name = try XCTUnwrap((column as? String) ?? (column as? NSAttributeDescription)?.name)
                let attribute = try XCTUnwrap(entity.attributesByName[name])
                XCTAssertFalse(attribute.isOptional, "\(name) is optional, which disables the dedup for its nil rows")
            }
        }
    }

    func testTheModelHoldsThisOneEntityOnly() throws {
        let model = try loadModel()
        XCTAssertEqual(model.entities.map(\.name), [Self.entityName])
    }

}
