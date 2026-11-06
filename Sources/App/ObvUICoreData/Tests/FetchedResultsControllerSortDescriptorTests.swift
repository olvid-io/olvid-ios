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

import XCTest
import CoreData
import ObvCrypto
import ObvTypes
@testable import ObvUICoreData


/// Regression tests for the crash reported by two beta users on 4.4 (984), one sending a link (hence a link preview, hence an
/// attachment) into a group of four, the other a voice message:
///
/// ```
/// -[__NSCFData compare:]: unrecognized selector sent to instance 0x…
///   Foundation  _NSCompareObject
///   CoreData    +[NSFetchedResultsController _insertIndexForObject:inArray:lowIdx:highIdx:sortDescriptors:]
///   CoreData    -[NSFetchedResultsController _updateFetchedObjectsWithInsertChange:]
///   CoreData    -[NSFetchedResultsController(PrivateMethods) _updateFetchedObjectsWithInsertedObjects:deletedObjects:updatedObjects:]
///   …
///   CoreData    -[NSManagedObjectContext mergeChangesFromContextDidSaveNotification:]
/// ```
///
/// **A fetched results controller places a row *in memory* whenever a change is merged into its context, and it does so by
/// sending `compare:` to the sort-descriptor values.** `NSData` does not implement `compare:`, and neither does `NSUUID`. The
/// SQL fetch is unaffected — SQLite orders blobs happily — so a controller sorted on a binary attribute works in everything
/// that merely fetches, and aborts the process the first time somebody else's save reaches it.
///
/// The controller that did it watched the *recipients* of one sent message (``PersistedMessageSentRecipientInfos``, sorted on
/// `messageIdentifierFromEngine`), one being created per attachment cell of the SwiftUI discussion screen. What the tests
/// below establish, rather than argue, is how narrow the fault actually is — every one of these was measured on 2026-09-04,
/// and two of them contradict what the crash reports were first read to mean:
///
/// - **Only an *insert* compares.** An update of the sorted value, an update that reverses the rows' order, and a save merged
///   in after the controller has fetched the same rows all leave it alone. So the save that gives a message's recipients
///   their identifiers is *not* what crashed the app, though it writes exactly the value being sorted on.
/// - **One row already held is enough**, an insert into an array of one still costing one comparison. Nothing about the
///   number of recipients protects anybody.
/// - **A comparison involving nil is answered without `compare:`.** This matters because a freshly inserted recipient-infos
///   row always carries a nil identifier — see the comment in
///   `PersistedMessageSentRecipientInfos.init(recipientIdentity:messageSent:)` — so an insert of one is safe *unless the
///   same save also sets the identifier*, which is what `setValuesReceivedFromAnotherOwnedDevice(...)` does.
///
/// A test cannot say which of the five controllers fired in the field, and these do not try to. What they do is fix the
/// mechanism in place, and guard every controller we have against acquiring such a sort descriptor again.
final class FetchedResultsControllerSortDescriptorTests: XCTestCase {

    // MARK: - The guard on our own controllers

    /// Builds the fetched results controllers whose sort descriptors named a binary or a UUID attribute, and asserts that no
    /// sort descriptor of theirs names a value that cannot be compared in memory.
    ///
    /// The controllers are only *built* here: no fetch is executed, so the stand-in objects need not be valid and nothing is
    /// ever saved. **Add any new controller to the list below**, especially one that watches several rows.
    func testTheAppsFetchedResultsControllersNeverSortOnAValueThatCannotBeCompared() throws {

        let context = try Self.makeInMemoryObvMessengerContext()
        let model = try XCTUnwrap(context.persistentStoreCoordinator?.managedObjectModel)

        // Stand-ins for the objects the controllers are asked about. Inserted bare, never validated, never saved: all the
        // predicates need is an object ID, and the fetch requests are not executed.

        let messageSent = NSEntityDescription.insertNewObject(forEntityName: "PersistedMessageSent", into: context)
        let discussion = try XCTUnwrap(NSEntityDescription.insertNewObject(forEntityName: "PersistedOneToOneDiscussion", into: context) as? PersistedDiscussion)

        let contactIdentifier = ObvContactIdentifier(contactCryptoId: Self.contactCryptoId, ownedCryptoId: Self.ownedCryptoId)
        let contactDeviceIdentifier = ObvContactDeviceIdentifier(
            ownedCryptoId: Self.ownedCryptoId,
            contactCryptoId: Self.contactCryptoId,
            deviceUID: try XCTUnwrap(UID(uid: Data(repeating: 0x01, count: 32))))

        var controllers: [(name: String, entityName: String, sortDescriptors: [NSSortDescriptor])] = []

        func examine<T: NSManagedObject>(_ name: String, _ frc: NSFetchedResultsController<T>) throws {
            let entityName = try XCTUnwrap(frc.fetchRequest.entityName ?? frc.fetchRequest.entity?.name)
            controllers.append((name, entityName, frc.fetchRequest.sortDescriptors ?? []))
        }

        try examine("PersistedMessageSentRecipientInfos.getFetchedResultsControllerForInfos(ofMessageWithObjectID:)",
                    PersistedMessageSentRecipientInfos.getFetchedResultsControllerForInfos(ofMessageWithObjectID: messageSent.objectID, within: context))

        try examine("PersistedObvContactDevice.getFetchedResultsController(contactDeviceIdentifier:)",
                    PersistedObvContactDevice.getFetchedResultsController(contactDeviceIdentifier: contactDeviceIdentifier, within: context))

        try examine("PersistedObvContactDevice.getFetchedResultsController(contactIdentifier:)",
                    PersistedObvContactDevice.getFetchedResultsController(contactIdentifier: contactIdentifier, within: context))

        try examine("PersistedDraft.getFetchedResultsControllerForPersistedDraft(of:)",
                    PersistedDraft.getFetchedResultsControllerForPersistedDraft(of: discussion, within: context))

        try examine("PersistedDraft.getFetchedResultsControllerForPersistedDraft(discussionObjectID:)",
                    PersistedDraft.getFetchedResultsControllerForPersistedDraft(discussionObjectID: .init(objectID: discussion.objectID), within: context))

        let draft = NSEntityDescription.insertNewObject(forEntityName: "PersistedDraft", into: context)

        try examine("PersistedDraftFyleJoinVariant.getFetchedResultsControllerForAllVariantsOfDraft(withObjectID:)",
                    PersistedDraftFyleJoinVariant.getFetchedResultsControllerForAllVariantsOfDraft(withObjectID: .init(objectID: draft.objectID), within: context))

        try examine("PersistedObvContactIdentity.getFetchedResultsControllerForSuggestions(ownedCryptoId:)",
                    PersistedObvContactIdentity.getFetchedResultsControllerForSuggestions(ownedCryptoId: Self.ownedCryptoId, within: context))

        try examine("PersistedObvContactIdentity.getFetchedResultsControllerForAllWhoCouldBeInvited(ownedCryptoId:)",
                    PersistedObvContactIdentity.getFetchedResultsControllerForAllWhoCouldBeInvited(ownedCryptoId: Self.ownedCryptoId, within: context))

        // The list must not silently become empty, and every key must actually resolve against the model: a renamed attribute
        // has to fail here rather than pass by not being looked at.

        XCTAssertEqual(controllers.count, 8, "The list of controllers under test has changed unexpectedly")

        for controller in controllers {
            for sortDescriptor in controller.sortDescriptors {
                let key = try XCTUnwrap(sortDescriptor.key, "\(controller.name) has a sort descriptor without a key")
                let attributeType = try Self.attributeType(forKeyPath: key, from: controller.entityName, in: model)
                XCTAssertTrue(
                    Self.canBeComparedInMemory(attributeType),
                    """
                    \(controller.name) sorts on \(controller.entityName).\(key), whose value cannot be compared in memory. \
                    A fetched results controller sends compare: to it when a change is merged in, and aborts the process.
                    """)
            }
        }

    }


    /// The types a fetched results controller may sort on, `compare:` being what it uses.
    ///
    /// An allow-list rather than a deny-list, so that a type nobody thought about (`URI`, whose `NSURL` has no `compare:`
    /// either) fails here instead of in the field.
    private static func canBeComparedInMemory(_ attributeType: NSAttributeType) -> Bool {
        switch attributeType {
        case .stringAttributeType,
                .dateAttributeType,
                .integer16AttributeType,
                .integer32AttributeType,
                .integer64AttributeType,
                .decimalAttributeType,
                .doubleAttributeType,
                .floatAttributeType,
                .booleanAttributeType:
            return true
        default:
            // .binaryDataAttributeType, .transformableAttributeType, .UUIDAttributeType, .URIAttributeType, .objectIDAttributeType, …
            return false
        }
    }


    /// Resolves a sort-descriptor key — possibly a dotted key path crossing relationships, as `Predicate.Key` composes them —
    /// to the type of the attribute it ends on. Throws when it names nothing, so that a stale key fails the test.
    private static func attributeType(forKeyPath keyPath: String, from entityName: String, in model: NSManagedObjectModel) throws -> NSAttributeType {

        guard var entity = model.entitiesByName[entityName] else { throw TestError.noSuchEntity(entityName) }

        let components = keyPath.split(separator: ".").map(String.init)
        guard let lastComponent = components.last else { throw TestError.emptyKeyPath }

        for component in components.dropLast() {
            guard let relationship = entity.relationshipsByName[component],
                  let destination = relationship.destinationEntity else {
                throw TestError.noSuchRelationship(component, inEntity: entity.name ?? "?")
            }
            entity = destination
        }

        guard let attribute = entity.attributesByName[lastComponent] else {
            throw TestError.noSuchAttribute(lastComponent, inEntity: entity.name ?? "?")
        }

        return attribute.attributeType

    }


    // MARK: - The shape our controllers have now

    /// No sort descriptor at all: every change merged in must be harmless, and must still be reported.
    func testMergingChangesIntoAControllerWithoutSortDescriptorsIsHarmless() throws {

        let updated = try TwoContextsOnOneStore(sortDescriptors: [], numberOfRows: 2, givesRowsABinaryValueUpfront: true)
        try updated.fetch()
        let afterAnUpdate = try updated.changeTheBinaryValueOfEveryRow()
        XCTAssertEqual(afterAnUpdate.numberOfFetchedRows, 2)
        XCTAssertTrue(afterAnUpdate.theControllerReportedAChange, "The controller was never told about the merge, so this proved nothing")

        let inserted = try TwoContextsOnOneStore(sortDescriptors: [], numberOfRows: 2, givesRowsABinaryValueUpfront: true)
        try inserted.fetch()
        let afterAnInsert = try inserted.insertOneMoreRow()
        XCTAssertEqual(afterAnInsert.numberOfFetchedRows, 3)
        XCTAssertTrue(afterAnInsert.theControllerReportedAChange)

    }


    // MARK: - The mechanism, and the conditions it needs

    /// **An insert is the only change that makes a controller compare anything**, and this is the one that crashed the app:
    /// a row placed beside another that carries a value. It is `_updateFetchedObjectsWithInsertChange:` in both reports.
    ///
    /// **Opt-in, because it may kill the process.** The exception is an `NSException` raised while Core Data merges, inside a
    /// notification posted from within `save()`. Whether anything catches it is not dependable: it was recorded as a plain
    /// test failure with one row already held, and as `Crash: xctest` with two, on the same machine within the hour. Left in
    /// CI it would take runs down at random, which is why it is behind an environment variable:
    ///
    /// ```
    /// TEST_RUNNER_OBV_RUN_THE_ABORTING_FRC_SORT_TEST=1 \
    ///   xcodebuild test -workspace Olvid.xcworkspace -scheme ObvUICoreData \
    ///   -destination 'platform=iOS Simulator,name=iPhone 17' \
    ///   -only-testing:ObvUICoreDataTests/FetchedResultsControllerSortDescriptorTests/testAnInsertBesideARowCarryingDataAbortsTheProcess
    /// ```
    ///
    /// Measured on 2026-09-04: `-[__NSCFData compare:]: unrecognized selector sent to instance 0x…`, the field crash's own
    /// words, and `Crash: xctest at closure #2 in TwoContextsOnOneStore.writingContextDidSave(_:)` — inside the merge, where
    /// both reports put it.
    func testAnInsertBesideARowCarryingDataAbortsTheProcess() throws {

        let environment = ProcessInfo.processInfo.environment

        try XCTSkipIf(environment["OBV_RUN_THE_ABORTING_FRC_SORT_TEST"] == nil,
                      "Opt-in: this test aborts the process when it reproduces the crash.")

        // One row already held is enough: the inserted row is placed by a binary search over the rows that are there, and a
        // search over one row still compares once. OBV_ABORTING_FRC_SORT_TEST_ROWS raises it.
        let numberOfRows = environment["OBV_ABORTING_FRC_SORT_TEST_ROWS"].flatMap(Int.init) ?? 1

        let harness = try TwoContextsOnOneStore(sortDescriptors: Self.sortedOnTheBinaryValue, numberOfRows: numberOfRows, givesRowsABinaryValueUpfront: true)
        try harness.fetch()
        _ = try harness.insertOneMoreRow()

        XCTFail("The insert was survived, which contradicts the diagnosis of the crash")

    }


    /// **The boundary of the fault, and it is narrower than it looks.** None of these three makes a controller sorted on a
    /// binary attribute compare anything, even with every row carrying a value:
    ///
    /// - an **update** of the sort value on every row;
    /// - an update that **reverses the rows' order**, so the controller cannot be skipping the work because the order is
    ///   unchanged;
    /// - a save **merged in after the controller has fetched the same rows** from the store, where it is handed rows it
    ///   already holds. It is not even told about that one — see the assertion below.
    ///
    /// Which is why the save that gives a message's recipients their identifiers cannot be what crashed the app, though it
    /// changes exactly the value that is sorted on. Something must genuinely **insert** a row.
    func testNoChangeOtherThanAnInsertMakesAControllerSortedOnDataCompareAnything() throws {

        let updated = try TwoContextsOnOneStore(sortDescriptors: Self.sortedOnTheBinaryValue, numberOfRows: 2, givesRowsABinaryValueUpfront: true)
        try updated.fetch()
        XCTAssertEqual(try updated.changeTheBinaryValueOfEveryRow().numberOfFetchedRows, 2)

        let reordered = try TwoContextsOnOneStore(sortDescriptors: Self.sortedOnTheBinaryValue, numberOfRows: 2, givesRowsABinaryValueUpfront: true)
        try reordered.fetch()
        XCTAssertEqual(try reordered.changeTheBinaryValueOfEveryRowReversingTheirOrder().numberOfFetchedRows, 2)

        let merged = try TwoContextsOnOneStore(sortDescriptors: Self.sortedOnTheBinaryValue,
                                               numberOfRows: 2,
                                               givesRowsABinaryValueUpfront: true,
                                               mergesSavesImmediately: false)
        try merged.fetch()
        let outcome = merged.mergeHeldSaves()
        XCTAssertEqual(outcome.numberOfFetchedRows, 2)
        XCTAssertFalse(outcome.theControllerReportedAChange, "A late merge of rows the controller already holds is expected to tell it nothing at all")

    }


    /// **Nothing is compared while the values are still nil**, whatever the provocation: a comparison involving nil is
    /// answered without sending `compare:` to anything. So the rows of a message that has not been posted yet are safe, and
    /// the fault needs at least two rows that already carry an identifier.
    func testNothingIsComparedWhileTheSortValuesAreStillNil() throws {

        let updated = try TwoContextsOnOneStore(sortDescriptors: Self.sortedOnTheBinaryValue, numberOfRows: 2)
        try updated.fetch()
        XCTAssertEqual(try updated.changeTheBinaryValueOfEveryRow().numberOfFetchedRows, 2)

        let inserted = try TwoContextsOnOneStore(sortDescriptors: Self.sortedOnTheBinaryValue, numberOfRows: 2)
        try inserted.fetch()
        XCTAssertEqual(try inserted.insertOneMoreRow().numberOfFetchedRows, 3)

    }


    private static let sortedOnTheBinaryValue = [NSSortDescriptor(key: TwoContextsOnOneStore.binaryAttributeName, ascending: true)]


}


// MARK: - The harness

extension FetchedResultsControllerSortDescriptorTests {

    /// Reproduces the app's shape on a purpose-built one-entity model: two private-queue contexts on one store, a controller
    /// on the watching context with a delegate (a controller without one does not track changes at all), and the writing
    /// context's saves merged in with `mergeChanges(fromContextDidSave:)`.
    ///
    /// A one-entity model rather than `ObvMessenger`, because this must really *save*, which the app's entities cannot do
    /// without a valid object graph — and what is under test is a behaviour of Core Data, not any of our entities. The one
    /// deliberate departure from the app is that the merge is synchronous, which is what lets XCTest see the exception rather
    /// than the process dying on it.
    fileprivate final class TwoContextsOnOneStore: NSObject, NSFetchedResultsControllerDelegate, @unchecked Sendable {

        static let entityName = "Row"
        static let binaryAttributeName = "blob"
        static let groupAttributeName = "group"

        struct Outcome {
            let numberOfFetchedRows: Int
            let theControllerReportedAChange: Bool
        }

        private let writingContext: NSManagedObjectContext
        private let watchingContext: NSManagedObjectContext
        private let controller: NSFetchedResultsController<NSManagedObject>
        private let mergesSavesImmediately: Bool

        private let storeDirectory: URL

        private let lock = NSLock()
        private var numberOfReportedChanges = 0
        private var heldNotifications: [Notification] = []


        /// - Parameters:
        ///   - numberOfRows: how many matching rows exist before the controller fetches.
        ///   - givesRowsABinaryValueUpfront: whether those rows carry a value — nil being what the recipients of a message
        ///     that has not been posted yet carry.
        ///   - mergesSavesImmediately: when false, saves are held back, so that the controller fetches the rows from the
        ///     store first and then meets them again as inserts.
        init(sortDescriptors: [NSSortDescriptor],
             numberOfRows: Int,
             givesRowsABinaryValueUpfront: Bool = false,
             mergesSavesImmediately: Bool = true) throws {

            self.mergesSavesImmediately = mergesSavesImmediately

            storeDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
            let coordinator = try Self.makeStoreForOneEntity(at: storeDirectory.appendingPathComponent("Row.sqlite"))

            writingContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
            writingContext.persistentStoreCoordinator = coordinator

            watchingContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
            watchingContext.persistentStoreCoordinator = coordinator

            let request = NSFetchRequest<NSManagedObject>(entityName: Self.entityName)
            request.predicate = NSComparisonPredicate(
                leftExpression: NSExpression(forKeyPath: Self.groupAttributeName),
                rightExpression: NSExpression(forConstantValue: "g"),
                modifier: .direct,
                type: .equalTo,
                options: [])
            request.sortDescriptors = sortDescriptors

            controller = NSFetchedResultsController(fetchRequest: request,
                                                    managedObjectContext: watchingContext,
                                                    sectionNameKeyPath: nil,
                                                    cacheName: nil)

            super.init()

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(writingContextDidSave(_:)),
                name: .NSManagedObjectContextDidSave,
                object: writingContext)

            try writingContext.performAndWait {
                for index in 0..<numberOfRows {
                    let row = NSEntityDescription.insertNewObject(forEntityName: Self.entityName, into: writingContext)
                    row.setValue("g", forKey: Self.groupAttributeName)
                    if givesRowsABinaryValueUpfront {
                        row.setValue(Data([UInt8(0x10 + index)]), forKey: Self.binaryAttributeName)
                    }
                }
                try writingContext.save()
            }

        }


        deinit {
            NotificationCenter.default.removeObserver(self)
            try? FileManager.default.removeItem(at: storeDirectory)
        }


        /// The controller fetches what is in the store.
        func fetch() throws {
            try watchingContext.performAndWait {
                controller.delegate = self
                try controller.performFetch()
            }
        }


        /// Every row is given a *different* binary value in one save — as the identifiers of one message's recipients arrive,
        /// and as a receipt's timestamp later does.
        func changeTheBinaryValueOfEveryRow() throws -> Outcome {
            try writingContext.performAndWait {
                let rows = try writingContext.fetch(NSFetchRequest<NSManagedObject>(entityName: Self.entityName))
                for (index, row) in rows.enumerated() {
                    row.setValue(Data([UInt8(0x20 + index)]), forKey: Self.binaryAttributeName)
                }
                try writingContext.save() // Merged into the watching context before this returns
            }
            return outcome()
        }


        /// Every row is given a new binary value that **reverses their order**, the first row's becoming the greater. An
        /// update that leaves the order alone may cost the controller nothing; this one cannot.
        func changeTheBinaryValueOfEveryRowReversingTheirOrder() throws -> Outcome {
            try writingContext.performAndWait {
                let request = NSFetchRequest<NSManagedObject>(entityName: Self.entityName)
                request.sortDescriptors = [NSSortDescriptor(key: Self.binaryAttributeName, ascending: true)]
                let rows = try writingContext.fetch(request)
                for (index, row) in rows.enumerated() {
                    row.setValue(Data([UInt8(0xF0 - index)]), forKey: Self.binaryAttributeName)
                }
                try writingContext.save()
            }
            return outcome()
        }


        /// One more matching row, so that the controller is handed a genuinely new one while it already holds others.
        func insertOneMoreRow() throws -> Outcome {
            try writingContext.performAndWait {
                let row = NSEntityDescription.insertNewObject(forEntityName: Self.entityName, into: writingContext)
                row.setValue("g", forKey: Self.groupAttributeName)
                row.setValue(Data([0xFF]), forKey: Self.binaryAttributeName)
                try writingContext.save()
            }
            return outcome()
        }


        /// Delivers the saves that were held back, which is how the controller is made to meet rows it has *already* fetched
        /// from the store as freshly inserted ones.
        func mergeHeldSaves() -> Outcome {
            let notifications = lock.withLock {
                let held = heldNotifications
                heldNotifications = []
                return held
            }
            watchingContext.performAndWait {
                for notification in notifications {
                    watchingContext.mergeChanges(fromContextDidSave: notification)
                }
            }
            return outcome()
        }


        private func outcome() -> Outcome {
            var numberOfFetchedRows = 0
            watchingContext.performAndWait {
                numberOfFetchedRows = controller.fetchedObjects?.count ?? 0
            }
            return .init(numberOfFetchedRows: numberOfFetchedRows,
                         theControllerReportedAChange: lock.withLock { numberOfReportedChanges > 0 })
        }


        @objc private func writingContextDidSave(_ notification: Notification) {
            guard mergesSavesImmediately else {
                lock.withLock { heldNotifications.append(notification) }
                return
            }
            watchingContext.performAndWait {
                watchingContext.mergeChanges(fromContextDidSave: notification)
            }
        }


        /// What the controller reports is how we know the merge reached it at all, rather than a test passing because nothing
        /// ever happened.
        func controllerDidChangeContent(_ controller: NSFetchedResultsController<any NSFetchRequestResult>) {
            lock.withLock { numberOfReportedChanges += 1 }
        }


        /// One entity, `Row`, with the two attributes the harness needs: a binary one to sort on, and a string one to select
        /// on.
        ///
        /// **A SQLite store, on purpose, and not `NSInMemoryStoreType`.** The in-memory store orders rows *in memory*, so it
        /// sends `compare:` to them during `performFetch` itself — which crashed this harness before the controller was ever
        /// asked anything, and would have credited the fetch's own sort to the controller. SQLite orders blobs in SQL, as
        /// the app's store does, which leaves the controller's in-memory placement as the only thing that can compare.
        private static func makeStoreForOneEntity(at storeURL: URL) throws -> NSPersistentStoreCoordinator {

            let blob = NSAttributeDescription()
            blob.name = binaryAttributeName
            blob.attributeType = .binaryDataAttributeType
            blob.isOptional = true

            let group = NSAttributeDescription()
            group.name = groupAttributeName
            group.attributeType = .stringAttributeType
            group.isOptional = true

            let entity = NSEntityDescription()
            entity.name = entityName
            entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
            entity.properties = [blob, group]

            let model = NSManagedObjectModel()
            model.entities = [entity]

            let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
            try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL, options: nil)
            return coordinator

        }

    }

}


// MARK: - Fixtures and the in-memory ObvMessenger stack

extension FetchedResultsControllerSortDescriptorTests {

    /// Two sample dev-server identities, as used by the other tests of this target.
    static let ownedCryptoId = try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f0000b82ae0c57e570389cb03d5ad93dab4606bda7bbe01c09ce5e423094a8603a61e01693046e10e04606ef4461d31e1aa1819222a0a606a250e91749095a4410778c1")!)
    static let contactCryptoId = try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f000009e171a9c73a0d6e9480b022154c83b13dfa8e4c99496c061c0c35b9b0432b3a014a5393f98a1aead77b813df0afee6b8af7e5f9a5aae6cb55fdb6bc5cc766f8da")!)


    /// Builds an in-memory `NSManagedObjectContext` backed by the compiled `ObvMessenger` model, as
    /// `PersistedMessageHistoryTransferDoubleInsertionTests` does: the model is compiled into the `ObvAppDatabase` framework
    /// bundle, and a `/dev/null` SQLite store keeps the database in memory. Nothing is ever saved through it here.
    static func makeInMemoryObvMessengerContext() throws -> NSManagedObjectContext {

        let momdURL = (Bundle.allFrameworks + Bundle.allBundles)
            .compactMap { $0.url(forResource: "ObvMessenger", withExtension: "momd") }
            .first

        guard let momdURL, let model = NSManagedObjectModel(contentsOf: momdURL) else {
            throw TestError.couldNotLoadObvMessengerModel
        }

        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        try coordinator.addPersistentStore(
            ofType: NSSQLiteStoreType,
            configurationName: nil,
            at: URL(fileURLWithPath: "/dev/null"),
            options: nil)

        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        return context

    }


    enum TestError: Error {
        case couldNotLoadObvMessengerModel
        case noSuchEntity(String)
        case noSuchRelationship(String, inEntity: String)
        case noSuchAttribute(String, inEntity: String)
        case emptyKeyPath
    }

}
