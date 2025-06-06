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
  

import UIKit
import CoreData
import ObvUICoreData

enum TappedStuffForCell {
    case hardlink(hardLink: HardLinkToFyle)
    case openLink(url: URL)
    case openExternalMapAt(latitude: Double, longitude: Double, address: String?)
    case openMap(messageObjectID: TypeSafeManagedObjectID<PersistedMessage>)
    case messageThatRequiresUserAction(messageObjectID: TypeSafeManagedObjectID<PersistedMessageReceived>)
    case receivedFyleMessageJoinWithStatusToResumeDownload(receivedJoinObjectID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>)
    case receivedFyleMessageJoinWithStatusToPauseDownload(receivedJoinObjectID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>)
    case sentFyleMessageJoinWithStatusReceivedFromOtherOwnedDeviceToResumeDownload(sentJoinObjectID: TypeSafeManagedObjectID<SentFyleMessageJoinWithStatus>)
    case sentFyleMessageJoinWithStatusReceivedFromOtherOwnedDeviceToPauseDownload(sentJoinObjectID: TypeSafeManagedObjectID<SentFyleMessageJoinWithStatus>)
    case reaction(messageObjectID: TypeSafeManagedObjectID<PersistedMessage>)
    case missedMessageBubble
    case circledInitials(contactObjectID: TypeSafeManagedObjectID<PersistedObvContactIdentity>)
    case replyTo(replyToMessageObjectID: NSManagedObjectID)
    case systemCellShowingUpdatedDiscussionSharedSettings
    case systemCellShowingCallLogItemRejectedIncomingCallBecauseOfDeniedRecordPermission
    case systemCellShowingCallLogItemRejectedBecauseOfVoIPSettings
    case behaveAsIfTheDiscussionTitleWasTapped
}


protocol UIViewWithTappableStuff: UIView {
    func tappedStuff(tapGestureRecognizer: UITapGestureRecognizer, acceptTapOutsideBounds: Bool) -> TappedStuffForCell?
}

extension UIViewWithTappableStuff {
    func tappedStuff(tapGestureRecognizer: UITapGestureRecognizer) -> TappedStuffForCell? {
        return tappedStuff(tapGestureRecognizer: tapGestureRecognizer, acceptTapOutsideBounds: false)
    }

}
