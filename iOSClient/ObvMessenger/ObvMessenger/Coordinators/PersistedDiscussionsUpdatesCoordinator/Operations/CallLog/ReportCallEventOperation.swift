/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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

import Foundation
import os.log
import ObvTypes
import ObvEngine
import OlvidUtils
import ObvCrypto
import ObvUI
import ObvUICoreData


final class ReportCallEventOperation: OperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {

    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: ReportCallEventOperation.self))

    let callUUID: UUID
    let callReport: CallReport
    let groupIdentifier: GroupIdentifierBasedOnObjectID?
    let ownedCryptoId: ObvCryptoId

    init(callUUID: UUID, callReport: CallReport, groupIdentifier: GroupIdentifierBasedOnObjectID?, ownedCryptoId: ObvCryptoId) {
        self.callUUID = callUUID
        self.callReport = callReport
        self.groupIdentifier = groupIdentifier
        self.ownedCryptoId = ownedCryptoId

        super.init()
    }

    override func main() {

        ObvStack.shared.performBackgroundTaskAndWait { context in
            os_log("☎️📖 Receive new callReport with %{public}@", log: log, type: .info, callReport.description)

            let isItemCreatedOrUpdated: Bool

            let item: PersistedCallLogItem
            do {
                if let _item = try PersistedCallLogItem.get(callUUID: callUUID, within: context) {
                    item = _item
                    isItemCreatedOrUpdated = false
                } else {
                    item = try PersistedCallLogItem(callUUID: callUUID,
                                                    ownedCryptoId: ownedCryptoId,
                                                    isIncoming: callReport.isIncoming,
                                                    unknownContactsCount: 0,
                                                    groupIdentifier: groupIdentifier,
                                                    within: context)
                    isItemCreatedOrUpdated = true
                }
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }


            let callReportKind = callReport.toCallReportKind

            for participantId in callReport.participantInfos {
                if let participantId = participantId,
                   let contactIdentity = try? PersistedObvContactIdentity.get(objectID: participantId.contactObjectID, within: context) {
                    if let logContact = item.logContacts.first(where: { $0.contactIdentity?.cryptoId == contactIdentity.cryptoId }) {
                        // Update the current contact with the last report.
                        logContact.callReportKind = callReportKind
                    } else {
                        _ = PersistedCallLogContact(callLogItem: item, callReportKind: callReportKind, contactIdentity: contactIdentity, isCaller: participantId.isCaller, within: context)
                    }
                } else {
                    item.incrementUnknownContactsCount()
                }
            }
            switch callReport {
            case .missedIncomingCall(_, participantCount: let participantCount):
                item.initialParticipantCount = participantCount
            case .filteredIncomingCall(_, participantCount: let participantCount):
                item.initialParticipantCount = participantCount
            case .rejectedIncomingCall(_, participantCount: let participantCount):
                item.initialParticipantCount = participantCount
            case .rejectedIncomingCallBecauseOfDeniedRecordPermission(_, participantCount: let participantCount):
                item.initialParticipantCount = participantCount
            case .acceptedIncomingCall, .acceptedOutgoingCall:
                if item.startDate == nil {
                    item.startDate = Date()
                }
            case .rejectedOutgoingCall:
                break
            case .busyOutgoingCall:
                break
            case .unansweredOutgoingCall:
                break
            case .uncompletedOutgoingCall:
                break
            case .newParticipantInIncomingCall:
                break
            case .newParticipantInOutgoingCall:
                break
            }

            do {
                try context.save(logOnFailure: log)
            } catch(let error) {
                return cancel(withReason: .coreDataError(error: error))
            }

            if isItemCreatedOrUpdated {
                ObvMessengerInternalNotification.newCallLogItem(objectID: item.typedObjectID).postOnDispatchQueue()
            } else {
                ObvMessengerInternalNotification.callLogItemWasUpdated(objectID: item.typedObjectID).postOnDispatchQueue()
            }
        }

    }

}
