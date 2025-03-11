/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import CoreData
import ObvUICoreData
import SwiftUI
import ObvAppTypes


protocol MapSharingViewActionsProtocol: AnyObject {    
    @MainActor func userWantsToSendLocation(_ locationData: ObvLocationData, discussionIdentifier: ObvDiscussionIdentifier)
    @MainActor func userWantsToShareLocationContinuously(expirationMode: SharingLocationExpirationMode, discussionIdentifier: ObvDiscussionIdentifier)
    @MainActor func userWantsToDismissMapView()
}

protocol MapSharingViewModelProtocol: ObservableObject {

    @MainActor var discussion: PersistedDiscussion { get }
    @MainActor var ownedIdentity: PersistedObvOwnedIdentity { get }
    
    @MainActor var sharingType: MapSharingType { get set }
    @MainActor var shouldFollowUser: Bool { get set }

    @MainActor func userWantsToSwitchType()
}

enum SharingLocationExpirationMode: String, CaseIterable {

    case anHour
    case infinity
    
    var expirationDate: Date? {
        switch self {
        case .infinity:
            return nil
        case .anHour:
            return Date.now.addingTimeInterval(.init(hours: 1))
        }
    }
    
    var text: Text {
        switch self {
        case .infinity:
            return Text("SHARE_TIME_INDEFINITELY")
        case .anHour:
            return Text("SHARE_TIME_ONE_HOUR")
        }
    }
    
    var image: Image {
        switch self {
        case .infinity:
            return Image(systemIcon: .infinity)
        case .anHour:
            return Image(systemIcon: .clock)
        }
    }
}

@MainActor
final class MapSharingViewModel: MapSharingViewModelProtocol {

    let ownedIdentity: PersistedObvOwnedIdentity
    let discussion: PersistedDiscussion
    let discussionIdentifier: ObvDiscussionIdentifier
    
    @Published var sharingType: MapSharingType = .continuous
    @Published var shouldFollowUser: Bool = true
    
    func userWantsToSwitchType() {
        sharingType.toggle()
        shouldFollowUser.toggle()
    }

    init(discussionIdentifier: ObvDiscussionIdentifier, viewContext: NSManagedObjectContext) throws {
        guard let discussion = try PersistedDiscussion.getPersistedDiscussion(discussionIdentifier: discussionIdentifier, within: viewContext) else {
            assertionFailure()
            throw ObvError.discussionIsNil
        }
        guard let ownedIdentity = discussion.ownedIdentity else { assertionFailure(); throw ObvError.ownedIdentityIsNil }
        self.discussionIdentifier = discussionIdentifier
        self.ownedIdentity = ownedIdentity
        self.discussion = discussion
    }
    
    enum ObvError: Error {
        case ownedIdentityIsNil
        case discussionIsNil
    }
    
}


enum MapSharingType {
    case continuous
    case landmark
    
    mutating func toggle() {
        switch self {
        case .continuous:
            self = .landmark
        case .landmark:
            self = .continuous
        }
    }
    
    var icon: Image {
        switch self {
        case .continuous:
            return Image(systemIcon: .mappin)
        case .landmark:
            return Image(systemIcon: .locationFill)
        }
    }
    
    var text: Text {
        switch self {
        case .continuous:
            return Text("SEND_CONTINUOUS")
        case .landmark:
            return Text("SEND_LANDMARK")
        }
    }
    
    var localizedName: String {
        switch self {
        case .continuous:
            return String(localized: "SEND_CONTINUOUS", bundle: Bundle(for: ObvLocationResources.self))
        case .landmark:
            return String(localized: "SEND_LANDMARK", bundle: Bundle(for: ObvLocationResources.self))
        }
    }
    
    var background: AnyShapeStyle {
        switch self {
        case .continuous:
            return AnyShapeStyle(Color.blue)
        case .landmark:
            return AnyShapeStyle(.ultraThinMaterial)
        }
    }
}
