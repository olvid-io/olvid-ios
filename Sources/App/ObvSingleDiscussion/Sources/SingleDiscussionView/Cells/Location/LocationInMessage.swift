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

import Foundation
import CoreData
import CoreGraphics
import ObvDesignSystem


/// The place a location message shows.
public struct LocationInMessage: Hashable, Sendable {

    /// Identifies the **message**, and not the location it currently holds.
    ///
    /// That is deliberate, and it is the one place this differs from an attachment. A shared location is an object of its own, which is *deleted* the moment
    /// sharing ends — and a message whose sharing has ended still has something to draw. The message is therefore the stable identity, and what is asked about it
    /// is which location it has now.
    public let identifier: Identifier

    public enum Identifier: Hashable, Sendable {
        /// The object ID of a `PersistedMessage`, enforced by the data source — this module knows nothing of the persistence layer. Object IDs must not escape
        /// into anything persisted or crossing a process boundary.
        case objectID(_ objectID: NSManagedObjectID)
        case forPreview(_ uuid: UUID)
    }

    public let kind: Kind

    /// How the sender is sharing, which decides what is drawn on the map and what a tap does.
    public enum Kind: Hashable, Sendable {

        /// One place, sent once. It never moves.
        case oneShot

        /// A place being shared as the sender moves.
        case continuous

        /// Sharing that has finished. There is no place left to show: the location object is severed from the message and deleted when sharing ends, so a message
        /// in this state knows only that it once carried one.
        ///
        /// Sharing whose expiry has *passed* is this too, which is a deliberate departure — see Step 9e of the plan. The legacy screen keeps calling that continuous
        /// and hides its map by making it transparent, which leaves a blank square with an avatar and a live button on it.
        case ended
    }

    /// Identifies the **location object** — what is watched, since it is what a sender rewrites as they move. Nil once sharing is over and there is no location
    /// left to watch.
    ///
    /// Distinct from ``identifier``, and both are needed: an action names the *message* it acts on, whereas a stream follows the *location* it reports. They part
    /// company exactly when sharing ends, the location being deleted while the message remains.
    public let locationIdentifier: Identifier?

    /// Where the place was when this model was built — a **seed**, and not the truth.
    ///
    /// It earns its place the way ``FollowedAttachment``'s `initialImage` does: without it, a bubble whose map is already rasterised and cached would still show a
    /// grey square for the frame or two its stream takes to say where the place is. What follows a sender who moves is
    /// ``SingleDiscussionCellViewDataSource/getAsyncStreamOfLocationState(forLocationWith:)``, and its answers replace this one.
    public let coordinate: LocationCoordinate?

    /// Whether this is the reader's own sharing, from *this* device — which is the only case in which it can be stopped from here, and the only one the legacy
    /// screen shows a countdown for.
    ///
    /// False for everything a contact shares, and false for the reader's own sharing from another of their devices: that one cannot be stopped from here either,
    /// so it is offered an itinerary like a contact's.
    public let isOwnSharingFromThisDevice: Bool

    /// Whose place this is, drawn as the mark at the centre of the map while sharing is live. Nil leaves the mark out, as the legacy screen does when it has no
    /// initials to draw.
    ///
    /// Taken from the *message* — its contact, or the owned identity — as the legacy screen does, rather than from the device the location came through. The two
    /// agree in every case that reaches a discussion, and `ObvAvatarViewModel(continuousLocation:)` is there for the day they need not.
    public let sharer: ObvAvatarViewModel?

    public init(identifier: Identifier, locationIdentifier: Identifier?, kind: Kind, coordinate: LocationCoordinate?, isOwnSharingFromThisDevice: Bool, sharer: ObvAvatarViewModel?) {
        self.identifier = identifier
        self.locationIdentifier = locationIdentifier
        self.kind = kind
        self.coordinate = coordinate
        self.isOwnSharingFromThisDevice = isOwnSharingFromThisDevice
        self.sharer = sharer
    }

}


/// What the reader can ask of a place.
///
/// Its own enum, as an attachment's and a recording's actions have, for the reason ``AudioAction`` gives: a case names what it does as a method name would, while
/// staying something that can be logged, passed on and exhausted by the compiler.
public enum LocationAction: Sendable {

    /// Show the reader where this is. **Which map**, they neither know nor say: a location being shared opens the map inside the app so that the sharer can be
    /// followed, and everything else — a place sent once, or a device too old for that map — opens whichever maps app is installed. Only the app knows which of
    /// those is possible, so only the app decides.
    case showOnAMap

    /// Take the reader there. Always leaves the app for a maps application, even where ``showOnAMap`` would have stayed in it: following someone and being routed
    /// to them are two different wishes, and the legacy screen keeps them apart the same way.
    case itinerary

    /// Stop sharing. Offered only for the reader's own sharing from *this* device, that being the only sharing this device can end.
    case stopSharing

}


/// A place on the Earth, and nothing else.
///
/// Its own type rather than a `CLLocationCoordinate2D` for the reason `ObvLocationCoordinate2D` exists in `ObvLocation`: Apple's type is neither `Equatable`,
/// `Hashable` nor `Sendable`, and all three are wanted here — a coordinate is part of a message's model, and it is the identity of a request for a picture.
public struct LocationCoordinate: Hashable, Sendable {

    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// The same place, rounded to about the nearest metre — which is the smallest movement the bubble can show.
    ///
    /// **The unit that matters here is a point, not a degree.** The map is drawn 200pt across a span of 0.002°, some 223m, so one point is a little over a metre: a
    /// sender who moves a metre moves the picture by one point, which is not worth rasterising a map for, and a sender who has not moved at all must land on the
    /// same value or the cache is useless. Five decimal places of latitude is 1.11m, so that is where it is cut.
    ///
    /// Used for the *identity* of a request as well as for its cache key, so that a coordinate arriving a few centimetres from the last one starts nothing.
    public var quantisedToAboutAMetre: Self {
        .init(latitude: (latitude * Self.placesKept).rounded() / Self.placesKept,
              longitude: (longitude * Self.placesKept).rounded() / Self.placesKept)
    }

    /// 10⁵, five decimal places: 1.11m of latitude, and less than that of longitude everywhere outside the equator.
    private static let placesKept = 100_000.0

}


/// What a place *currently* is, as opposed to what its message says about it.
///
/// Everything here is rewritten as a sender moves — `updateContentForContinuousLocation(with:count:)` writes the coordinate, the address and the count on the
/// location and touches no message — so none of it can live in a message's model without a move costing a pass over the whole discussion. This is the second
/// cadence, in the shape ``AttachmentState`` and ``AttachmentProgress`` already have.
public struct LocationState: Sendable, Equatable {

    /// Where the place is now, and nil once there is no place left: sharing that ended deletes the location, and the stream then says so rather than falling silent.
    public let coordinate: LocationCoordinate?

    /// What the sender's device says the place is called. Rewritten as they move, which is why it is here and not in the message's model.
    public let address: String?

    /// When the sharing ends of its own accord, for the countdown badge. Nil for a place sent once, for sharing with no end set, and for sharing already over.
    public let expiration: Date?

    public init(coordinate: LocationCoordinate?, address: String?, expiration: Date?) {
        self.coordinate = coordinate
        self.address = address
        self.expiration = expiration
    }

}


/// Which way round a map is drawn, so that a picture of one can be asked for without the request knowing anything of SwiftUI.
public enum MapAppearance: Hashable, Sendable {
    case light
    case dark
}


/// What a place is doing, and a picture of the map around it.
///
/// A protocol of its own, alongside ``AttachmentProgressDataSource``, ``AudioPlaybackDataSource`` and ``LinkPreviewDataSource``, so that what this screen asks of
/// its app stays legible one question at a time.
@MainActor
public protocol LocationDataSource: AnyObject {

    /// Follows one place: where it is, what it is called, and when its sharing runs out — again each time any of that changes.
    ///
    /// **It watches the location, and not the message showing it**, which is the whole reason it exists: an update writes the `PersistedLocation` and leaves every
    /// message alone, so a screen watching only its messages never learns that a sender has moved. The identifier is therefore the location's, and it is nil — with
    /// no stream to open — once sharing is over.
    ///
    /// It stays open, and it reports a coordinate of nil rather than finishing when the place it followed is deleted: a bubble that has been showing a map needs to
    /// be told to stop, not merely left without news.
    ///
    /// Unlike the streams of models, this one takes no `streamUUID` and has no counterpart to finish it: a caller that loses interest cancels the task it is
    /// iterating in, and the implementation is expected to tear down whatever it was watching then. The same contract as
    /// ``SingleDiscussionCellViewDataSource/getAsyncStreamOfStateForAttachment(_:pixelSize:)``.
    func getAsyncStreamOfLocationState(forLocationWith identifier: LocationInMessage.Identifier) -> AsyncStream<LocationState>

    /// A still picture of the map around a place, ready to draw.
    ///
    /// **A still picture, and not a map view.** The legacy screen puts an `MKMapView` in the bubble with its zooming, scrolling, pitching and rotating all
    /// disabled — so what a reader sees is already a picture, and a picture is what a scrolling list can afford: a live map view per visible row is a heavyweight
    /// object with its own renderer and its own tile loading. It is also the only shape that works on iOS 16, where displaying a location has never been gated,
    /// while SwiftUI's `Map` there is the deprecated `Map(coordinateRegion:)`.
    ///
    /// A single answer rather than a stream, for the reason ``SingleDiscussionCellViewDataSource/recordingForAudioAttachment(_:numberOfSamples:)`` gives: for a
    /// given place there is no cruder version worth showing first, and nothing changes once it is known. A location that *moves* is a new place, and therefore a
    /// new request.
    ///
    /// **In points, with the scale beside them** — which is where this departs from every other picture on this screen, all of them asked for in pixels. A
    /// photograph is *decoded*, so only the pixels it is decoded to matter. A map is *rasterised*: the point size decides how large its street names and its
    /// buildings are drawn, and the scale decides how many pixels each of them gets. Asked for in pixels alone, a map would come back with labels too small to
    /// read on any device whose scale is not 1.
    ///
    /// A `CGImage` all the same: already rasterised, `Sendable`, and the same type on every Apple platform. Rasterising is real work and belongs off the main
    /// actor, with the answer remembered.
    ///
    /// The appearance is part of the request because a snapshot bakes light or dark map tiles into its pixels, and a reader can change theme with the screen
    /// open.
    ///
    /// Nil when there is nothing to draw — no tiles to be had offline, or a rasterisation that failed. A caller is expected to keep whatever it was already
    /// showing rather than blank the bubble.
    func mapSnapshot(centeredOn coordinate: LocationCoordinate, pointSize: CGSize, displayScale: CGFloat, appearance: MapAppearance) async -> CGImage?

}
