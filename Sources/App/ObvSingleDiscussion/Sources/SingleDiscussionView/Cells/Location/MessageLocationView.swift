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

import SwiftUI
import ObvDesignSystem
import ObvLocation
import ObvSystemIcon


/// The place a location message shows: a square of map, centred on it.
///
/// Matches the bubble of `LocationView` on the legacy screen — 200pt square, `systemFill`, a map that cannot be interacted with, and, laid over it, the pin of a
/// location sent once or the avatar of whoever is sharing theirs, the address along the bottom and the countdown of an expiry.
///
/// **Every mark sits at the centre, and none of them is a map annotation**: the coordinate *is* the centre of the region asked for, so nothing has to be projected.
/// The legacy view places its own subviews the same way, which is what makes this cheap to reproduce.
///
/// **Where the place is comes from a stream of its own, and not from the message's model.** A sender who moves rewrites their location and touches no message, so
/// nothing else would say so; and a coordinate reaching a bubble through its message would cost a pass over the whole discussion each time it changed. The model's
/// coordinate is kept as a seed for the first frame, exactly as `FollowedAttachment` keeps an initial image.
struct MessageLocationView: View {

    let location: LocationInMessage

    /// Whether the message is one the reader sent, which is the only thing that says whose sharing has ended: once it is over, the location is gone and with it every
    /// trace of who was sharing. The cell knows, being one kind of cell or the other.
    let style: MessageBubbleStyle

    let dataSource: any SingleDiscussionCellViewDataSource
    let actions: any SingleDiscussionCellViewActions

    @State private var map: CGImage?

    /// What the place currently is, as its own stream reports it. Nil until it has said anything, which is why the model's seed answers for the first frame.
    @State private var state: LocationState?

    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme

    /// The bubble is square, and the same square a single image gets: `SingleImageView.imageSize`, which `LocationView` adopts for its own width and height and
    /// returns as its `intrinsicContentSize`.
    static let side = CGFloat(200)

    /// In points, and not in pixels as every other picture on this screen is asked for: see ``LocationDataSource/mapSnapshot(centeredOn:pointSize:displayScale:appearance:)``.
    private static let pointSize = CGSize(width: side, height: side)

    private var appearance: MapAppearance {
        colorScheme == .dark ? .dark : .light
    }

    /// Where the place is, quantised to the metre the bubble can actually show: the stream's answer once it has spoken, and the model's seed until then.
    ///
    /// The seed is *dropped* the moment a state arrives, rather than kept as a fallback — as `FollowedAttachment` drops its own. What the stream says is the truth
    /// about where the place *is*.
    ///
    /// **But the model is what says whether there is a place at all**, and it outranks anything the stream last said. Sharing that ends severs the location from its
    /// message, which rebuilds the model as ``LocationInMessage/Kind/ended`` *and* leaves nothing to watch — so the stream is torn down before it can report the
    /// disappearance, and its final answer would otherwise keep a map on screen for a place nobody is at any more. That was seen: after stopping one's own sharing,
    /// a map with no mark and no button on it.
    private var coordinate: LocationCoordinate? {
        guard location.kind != .ended else { return nil }
        let current = state == nil ? location.coordinate : state?.coordinate
        return current?.quantisedToAboutAMetre
    }

    private var address: String? {
        state?.address
    }

    private var expiration: Date? {
        state?.expiration
    }

    var body: some View {
        // A single-root container, so that this view stays *unary* whichever of its states it is in. See `SingleDiscussionCellView`.
        VStack(spacing: 0) {
            if let map {
                Image(decorative: map, scale: displayScale)
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: Self.side, height: Self.side)
        // Held whether or not there is a picture yet, so that the row is its final height from the first frame: the map arriving must not move the discussion.
        // `systemFill` is the legacy bubble's own colour while a map has nothing to draw; sharing that is over has its own, paler one.
        .background(backgroundOfTheBubble)
        // Before the clipping, so that the address strip's own corners are cut by the bubble's.
        .overlay(alignment: .center) { markAtTheCentre }
        .overlay(alignment: .center) { whatSaysSharingIsOver }
        .overlay(alignment: .bottom) { addressAlongTheBottom }
        .overlay(alignment: .topLeading) { countdownBadge }
        .overlay(alignment: .bottom) { theButton }
        .clipShape(RoundedRectangle(cornerRadius: MessageBubbleMetrics.cornerRadius, style: .continuous))
        .contentShape(.rect)
        // A tap anywhere shows the place, exactly as on the legacy screen — except on sharing that is over, which has no place left to show and where
        // `LocationView.tappedStuff` likewise answers with nothing.
        .onTapGesture {
            guard location.kind != .ended, let coordinate else { return }
            Task { await actions.userWantsToActOnLocation(location, at: coordinate, address: address, action: .showOnAMap) }
        }
        // Keyed on the place *as quantised*, so that a sender shuffling about within a metre starts no render at all — and so that the render for a place left
        // behind is cancelled the moment there is a new one.
        .task(id: TaskIdentity(coordinate: coordinate, displayScale: displayScale, appearance: appearance)) {
            await asksForTheMap()
        }
        // Keyed on the location rather than the message: it is the location that changes, and it is nil — with nothing to follow — once sharing is over.
        .task(id: location.locationIdentifier) {
            await followsThePlace()
        }
    }


    /// Follows the place for as long as this view is on screen rather than taking its first answer: that is the whole point of it, a sender being free to move.
    private func followsThePlace() async {
        guard let locationIdentifier = location.locationIdentifier else {
            // Nothing left to follow, so nothing left to remember: the address and the countdown go with the place.
            state = nil
            return
        }
        for await reported in dataSource.getAsyncStreamOfLocationState(forLocationWith: locationIdentifier) {
            state = reported
        }
    }


    // MARK: The marks


    /// What sits on the place itself: a pin for a location sent once, the sharer's avatar while they are sharing, and nothing at all once sharing is over.
    @ViewBuilder private var markAtTheCentre: some View {
        switch location.kind {
        case .oneShot:
            pin
        case .continuous:
            if let sharer = location.sharer {
                // `ObvAvatarStyle.map` *is* the legacy usermark: a white disc with the avatar inset, 30pt across leaving it the 26pt the legacy view gives it. Only
                // the drop shadow is added here, that style having none of its own.
                ObvAvatarView(model: sharer,
                              style: .map,
                              size: .custom(frameSize: .init(width: Self.sideOfTheMark, height: Self.sideOfTheMark)),
                              dataSource: dataSource)
                    .shadow(color: .black.opacity(Self.opacityOfTheShadows), radius: 3, x: 0, y: 3)
            }
        case .ended:
            // The mark belongs to the panel below, which places it over its halo.
            EmptyView()
        }
    }


    /// What a bubble shows once there is no place left: the sharer's mark over a soft halo, and a sentence under it.
    ///
    /// **Whose sharing it was decides the sentence**, and the reader's own says so — "You stopped sharing location", in blue on a pale blue square, where a contact's
    /// says "Location expired" in grey. The legacy screen has both, and as far as its code shows it can only ever reach the second: the blue one needs
    /// `userCanStopSharingLocation`, which reads a relationship severed at the very instant sharing ends. Ours takes it from the *cell*, which cannot go stale.
    @ViewBuilder private var whatSaysSharingIsOver: some View {
        if location.kind == .ended {
            VStack(spacing: 0) {
                if let sharer = location.sharer {
                    ObvAvatarView(model: sharer,
                                  style: .map,
                                  size: .custom(frameSize: .init(width: Self.sideOfTheMark, height: Self.sideOfTheMark)),
                                  dataSource: dataSource)
                        // The pulse the legacy screen draws behind the mark, as a radial gradient in its own pale blue.
                        .background {
                            RadialGradient(colors: [Self.colorOfTheHalo.opacity(0.22), Self.colorOfTheHalo.opacity(0.8)],
                                           center: .center,
                                           startRadius: 0,
                                           endRadius: Self.sideOfTheHalo / 2)
                                .clipShape(Circle())
                                .frame(width: Self.sideOfTheHalo, height: Self.sideOfTheHalo)
                        }
                        .padding(.bottom, Self.gapUnderTheMark)
                }
                Text(sentenceSayingSharingIsOver)
                    .font(.body)
                    .foregroundStyle(colorOfTheSentence)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Self.horizontalInsetOfTheSentence)
            }
        }
    }


    private var sentenceSayingSharingIsOver: LocalizedStringKey {
        switch style {
        case .sent: return "LOCATION_SHARED_STOPPED"
        case .received: return "LOCATION_EXPIRED"
        }
    }


    private var colorOfTheSentence: Color {
        switch style {
        case .sent: return Self.colorOfTheSentenceWhenItWasOurs
        case .received: return Color(UIColor.secondaryLabel)
        }
    }


    /// `systemFill` while a map is being drawn, and the paler squares the legacy screen uses once sharing is over — its own light blue for the reader's own, and
    /// `tertiarySystemFill` for a contact's.
    private var backgroundOfTheBubble: Color {
        guard location.kind == .ended else { return Color(UIColor.systemFill) }
        switch style {
        case .sent: return Self.colorOfTheBubbleWhenItWasOurs
        case .received: return Color(UIColor.tertiarySystemFill)
        }
    }


    /// The teardrop of a location sent once, standing on the dot that marks the exact place.
    ///
    /// The shape is `DropPin` from `ObvLocation`, which the sharing map draws too — at its own size, which is why the sizes are here and the bezier is there. The
    /// pair is lifted so that the **dot**, and not the pair, is centred on the coordinate.
    private var pin: some View {
        VStack(spacing: 0) {
            ZStack {
                DropPin()
                    .fill(.white)
                Circle()
                    .fill(.red)
                    .frame(width: Self.sideOfTheDiscInThePin, height: Self.sideOfTheDiscInThePin)
                Image(systemIcon: .mappin)
                    .font(.system(size: Self.sizeOfTheGlyphInThePin))
                    .foregroundStyle(.white)
            }
            .frame(width: Self.widthOfThePin, height: Self.heightOfThePin)
            ZStack {
                Circle()
                    .fill(.white)
                Circle()
                    .fill(.red)
                    .frame(width: Self.sideOfTheDot - 2 * Self.insetOfTheDot, height: Self.sideOfTheDot - 2 * Self.insetOfTheDot)
            }
            .frame(width: Self.sideOfTheDot, height: Self.sideOfTheDot)
            .shadow(color: .black.opacity(Self.opacityOfTheShadows), radius: 2, x: 0, y: 1)
        }
        .offset(y: -(Self.heightOfThePin + Self.sideOfTheDot) / 2 + Self.sideOfTheDot / 2)
    }


    /// What the place is called, on the blurred strip the legacy view puts along the bottom edge.
    ///
    /// Every `", "` becomes a newline, as it does there, so an address arrives as its lines rather than as one long sentence — and it is left uncapped, which on a
    /// 200pt square means a long address can take a good part of the map. That is what a reader sees today.
    @ViewBuilder private var addressAlongTheBottom: some View {
        if let address, !address.isEmpty {
            Text(verbatim: address.replacingOccurrences(of: ", ", with: "\n"))
                .font(.caption2)
                .foregroundStyle(Color(UIColor.secondaryLabel))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Self.insetOfTheAddress)
                .background(.thinMaterial)
        }
    }


    /// How long is left of the reader's own sharing, in the orange badge the legacy view puts in the top-left corner.
    ///
    /// Shown for **the reader's own sharing from this device only**, as on the legacy screen: a contact's sharing has an end the reader cannot act on, and so has
    /// their own from another device. It does not tick — it says what the model said when the cell was built, which is all the legacy screen does either. A
    /// countdown that runs belongs with the ephemeral timers of Step 24.
    @ViewBuilder private var countdownBadge: some View {
        if location.kind == .continuous,
           location.isOwnSharingFromThisDevice,
           let expiration,
           let remaining = Self.formatted(remainingUntil: expiration) {
            HStack(spacing: 0) {
                Image(systemIcon: .clock)
                    .foregroundStyle(.white)
                    .padding(.leading, 2)
                Text(verbatim: remaining)
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .padding(.trailing, 6)
            }
            .frame(height: Self.heightOfTheBadge)
            .background(Self.colorOfTheBadge, in: RoundedRectangle(cornerRadius: Self.heightOfTheBadge / 2, style: .continuous))
            .padding(Self.insetOfTheBadge)
        }
    }


    /// The one button of a bubble showing live sharing, which has two faces: **red Stop** on the reader's own sharing from this device, and **blue Itinerary** on
    /// everything else — a contact's sharing, and their own from another of their devices, neither of which can be stopped from here.
    ///
    /// That is `LocationView`'s `messageSentFromCurrentDevice` decision, and it is the same button there too. An itinerary always leaves the app, even on the iOS
    /// versions where tapping the map itself stays in it: `LocationView` sends the button to `locationViewUserWantsToOpenMapAt` and the map to `.openMap`, which are
    /// not the same wish.
    @ViewBuilder private var theButton: some View {
        if location.kind == .continuous {
            Button {
                guard let coordinate else { return }
                let action: LocationAction = location.isOwnSharingFromThisDevice ? .stopSharing : .itinerary
                Task { await actions.userWantsToActOnLocation(location, at: coordinate, address: address, action: action) }
            } label: {
                Text(location.isOwnSharingFromThisDevice ? "BUTTON_LOCATION_STOP_SHARING" : "BUTTON_LOCATION_ITINERARY")
                    .font(.system(size: Self.sizeOfTheButtonTitle, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, Self.horizontalInsetOfTheButton)
                    .frame(height: Self.heightOfTheButton)
                    .background(location.isOwnSharingFromThisDevice ? Color.red : Self.colorOfTheItineraryButton,
                                in: RoundedRectangle(cornerRadius: Self.cornerRadiusOfTheButton, style: .continuous))
            }
            .buttonStyle(.plain)
            // **A hold here is not the start of a long press** — finding 18. Measured on an iPhone 13: a two-second hold shrank the message, opened Apple Maps on
            // release, and no menu at all. See ``AFingerOnThisIsNotAPressOnTheMessageEither``.
            .aFingerHereIsNotAPressOnTheMessage()
            .padding(.bottom, Self.insetOfTheButtonFromTheBottom)
        }
    }


    /// `LocationView.formatExpirationDate(with:)`: hours and minutes, abbreviated, and **nothing at all** once the date has passed — which is what hides the badge
    /// on sharing that has run out while still attached to its message.
    private static func formatted(remainingUntil expiration: Date) -> String? {
        guard expiration > Date.now else { return nil }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.hour, .minute]
        return formatter.string(from: Date.now, to: expiration)
    }


    // MARK: The measurements, every one of them `LocationView`'s

    /// `usermarkContainerView`, the white disc holding the sharer's avatar.
    private static let sideOfTheMark = CGFloat(30)

    /// `landmarkContainerView`, the white teardrop.
    private static let widthOfThePin = CGFloat(30)
    private static let heightOfThePin = CGFloat(45)

    /// `landmarkView`, the red disc inside it, and the `mappin` inside that.
    private static let sideOfTheDiscInThePin = CGFloat(26)
    private static let sizeOfTheGlyphInThePin = CGFloat(14)

    /// `pinpointContainerView`, the dot on the coordinate itself, and the inset of the red square within it.
    private static let sideOfTheDot = CGFloat(6)
    private static let insetOfTheDot = CGFloat(1)

    /// Every shadow the legacy view draws uses this one opacity.
    private static let opacityOfTheShadows = 0.33

    /// `addressLabel`'s insets, on all four sides.
    private static let insetOfTheAddress = CGFloat(8)

    /// `expirationContainerView`: 24pt tall, 8pt in from the top and leading edges, and its own orange.
    private static let heightOfTheBadge = CGFloat(24)
    private static let insetOfTheBadge = CGFloat(8)
    private static let colorOfTheBadge = Color(red: 240.0 / 255.0, green: 149.0 / 255.0, blue: 54.0 / 255.0)

    /// `actionButton`: 40pt tall, corner radius 10, its title 12pt semibold, content insets of 35 either side, and its bottom 24pt above the bubble's.
    private static let heightOfTheButton = CGFloat(40)
    private static let cornerRadiusOfTheButton = CGFloat(10)
    private static let sizeOfTheButtonTitle = CGFloat(12)
    private static let horizontalInsetOfTheButton = CGFloat(35)
    private static let insetOfTheButtonFromTheBottom = CGFloat(24)
    private static let colorOfTheItineraryButton = Color(red: 79.0 / 255.0, green: 174.0 / 255.0, blue: 237.0 / 255.0)

    /// The panel of sharing that is over: `stopUsermarkGradientView`'s 60pt halo in its pale blue, the mark 24pt above the sentence, which is inset 24 either side.
    private static let sideOfTheHalo = CGFloat(60)
    private static let gapUnderTheMark = CGFloat(24)
    private static let horizontalInsetOfTheSentence = CGFloat(24)
    private static let colorOfTheHalo = Color(red: 167.0 / 255.0, green: 221.0 / 255.0, blue: 251.0 / 255.0)

    /// The blue of "You stopped sharing location", and the very pale blue of the square it sits on — `stopSharingLabel`'s own colours.
    private static let colorOfTheSentenceWhenItWasOurs = Color(red: 73.0 / 255.0, green: 160.0 / 255.0, blue: 245.0 / 255.0)
    private static let colorOfTheBubbleWhenItWasOurs = Color(red: 238.0 / 255.0, green: 248.0 / 255.0, blue: 253.0 / 255.0)


    /// Asks for a picture of the place.
    ///
    /// **No place and no picture are not the same thing**, and telling them apart is the whole of this method. A request that comes back with nothing is a *failure
    /// to draw* — no tiles to be had offline, a rasterisation that gave up — and whatever is already on screen is nearly right, a few metres out at most, so
    /// blanking the square while the next one is made would be worse than leaving it. This is the one place this screen's usual rule is deliberately inverted.
    ///
    /// A coordinate of nil is the opposite: a definitive answer that there is no longer a place to show, because sharing ended and the location was severed from the
    /// message and deleted. Keeping the last map then leaves a reader looking at where someone *used* to be, with nothing to say that the sharing is over — and it
    /// does not even do so consistently, since a row rebuilt by a scroll comes back empty. So it is cleared. Step 9e replaces the emptiness with the panel the
    /// legacy screen draws.
    private func asksForTheMap() async {
        guard let coordinate else {
            map = nil
            return
        }
        guard let picture = await dataSource.mapSnapshot(centeredOn: coordinate, pointSize: Self.pointSize, displayScale: displayScale, appearance: appearance) else { return }
        // **A cancelled task must not write.** Rasterising a map takes long enough that the place it was asked about can stop being the place this view shows: when
        // sharing ends, SwiftUI cancels this task and starts another that clears the picture — but a cancelled task in Swift keeps running until it says otherwise,
        // so without this the render already in flight came back afterwards and put the old map up again. Seen as the square going grey and then filling in again.
        guard !Task.isCancelled else { return }
        map = picture
    }


    /// What makes the request worth making again — including the place itself, since a row is a view SwiftUI reuses for whatever message comes to occupy it.
    private struct TaskIdentity: Hashable {
        let coordinate: LocationCoordinate?
        let displayScale: CGFloat
        let appearance: MapAppearance
    }

}
