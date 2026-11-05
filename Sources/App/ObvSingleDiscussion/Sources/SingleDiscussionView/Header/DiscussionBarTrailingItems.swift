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
import ObvSystemIcon
import OlvidUtils


/// What a reader can ask of a discussion from its bar: the entries of the ellipsis menu, and the one action of the moon.
///
/// One value per entry rather than one closure per entry, for the reason ``AttachmentAction`` gives: a case names what it does as well as a method name would,
/// while being something that can be logged and passed on — and the compiler names every place that must answer when a case is added, which is what will happen
/// when Step 23 brings search back.
public enum DiscussionBarAction: Equatable, Sendable {

    /// Shows what this discussion's settings are — shared and local — as `settingsButtonTapped()` does.
    case showTheDiscussionSettings

    /// Shows everything ever attached to this discussion, as `galleryButtonTapped()` does. Still the UIKit gallery: Step 25 is the SwiftUI one.
    case showTheGallery

    /// Calls whoever this discussion is with, as `callButtonTapped()` does — one contact, or a chooser among a group's members.
    case call

    /// Clears the mute on this discussion. It only ever *clears* one: setting a mute lives in the discussion settings.
    case unmute

}


/// The ellipsis of the navigation bar, and everything under it.
///
/// **It draws nothing at all when it has nothing to offer**, which is the legacy behaviour and not an optimisation: `configureNavigationTitle()` builds its menu
/// elements first and only makes a button `if !menuElements.isEmpty`, so a locked discussion has no ellipsis whatever. A menu of no entries would be a button that
/// answers nothing.
///
/// **Search is here, and it is the one entry the app is not asked to perform.** Everything else in this menu presents something, which only something holding a view
/// controller can do; a search happens entirely inside this screen, so it arrives as a closure of its own rather than as a ``DiscussionBarAction``. That distinction
/// is worth keeping: the enum says what the *app* does.
///
/// It is also **the entry point legacy already uses on iOS** — `UIAction(title: Search, image: .magnifyingglass)`, calling `searchButtonTapped()`. So a reader has
/// never had to pull the discussion down to search; only the *field* moves in our version, from the navigation bar to the composition bar's place. Under Catalyst
/// legacy shows no entry, its field being permanently visible, and that is followed here.
struct DiscussionEllipsisMenu: View {

    let header: DiscussionHeader
    let act: (DiscussionBarAction) -> Void

    /// Asks the screen to search this discussion. Not a ``DiscussionBarAction``, for the reason above.
    let startASearch: () -> Void

    /// Asks the screen to let the reader choose several messages. **The second entry that is not a ``DiscussionBarAction``**, and for exactly the reason
    /// search is not one: nothing is presented, the screen simply changes what it is doing.
    let startSelectingMessages: () -> Void

    /// Whether there is anything to show. Asked by the caller, which leaves the whole `ToolbarItem` out rather than drawing an empty one — the legacy screen makes
    /// no button at all in that case, and an ellipsis that opens nothing would be worse than none.
    ///
    /// **Search does not need the discussion to be active**, so this answers yes whatever the status — which is what legacy does: it adds its search entry outside the
    /// `status == .active` test, so a locked discussion there has an ellipsis holding search alone.
    static func hasAnythingToOffer(_ header: DiscussionHeader) -> Bool {
        true
    }

    var body: some View {
        Menu {
            // The legacy order: the settings, the gallery, then the call.
            if header.isActive {
                Button { act(.showTheDiscussionSettings) } label: {
                    Label { Text("DISCUSSION_SETTINGS") } icon: { Image(systemIcon: .gearshapeFill) }
                }
                Button { act(.showTheGallery) } label: {
                    Label { Text("GALLERY") } icon: { Image(systemIcon: .photoOnRectangleAngled) }
                }
            }
            if header.isActive && header.isCallAvailable {
                Button { act(.call) } label: {
                    Label { Text("CALL") } icon: { Image(systemIcon: .phoneFill) }
                }
            }
            // **Above Search rather than below it**, so that Search stays the last entry as it is on the legacy screen. This one has no legacy position to preserve,
            // legacy having no way to choose several messages at all, so it takes the place that costs nothing.
            //
            // **Offered whatever the discussion's status**, as search is. A locked discussion is one a reader can no longer write in, and deleting what is already
            // there is precisely what they may still want to do — arguably the discussion where they want it most.
            Button(action: startSelectingMessages) {
                Label { Text("SELECT_MESSAGES") } icon: { Image(systemIcon: .checkmarkCircle) }
            }
            // Last, as it is on the legacy screen.
            //
            // **Offered on Catalyst too, where legacy does not offer it**, and that difference is deliberate rather than an oversight. Legacy leaves the entry out
            // there *because its field is permanently visible on that platform* — the entry would reveal something already shown. Ours is not: it appears in the
            // composition bar's place when asked for. Copying the exclusion without copying what justified it left Catalyst with no visible way to search at all, ⌘F
            // through the responder chain being the only one. Step 23c may put a permanent field on Mac, and if it does, this entry goes with it.
            //
            // `Search` is the key legacy's own entry uses, through `CommonString.Word.Search`, and it carries every translation the app has.
            Button(action: startASearch) {
                Label { Text("Search") } icon: { Image(systemIcon: .magnifyingglass) }
            }
        } label: {
            // `ellipsis` from iOS 26, where a bar item is drawn in a shape of the system's own, and `ellipsisCircle` before it, where it is not.
            Image(systemIcon: Self.icon)
        }
    }

    private static var icon: SystemIcon {
        if #available(iOS 26.0, *) {
            return .ellipsis
        } else {
            return .ellipsisCircle
        }
    }

}


/// The moon that says this discussion is muted, and the one action that unmutes it.
///
/// **It takes itself away when the mute ends.** A mute expiring is not something the database reports — `currentMuteNotificationsEndDate` merely starts answering
/// nil once the moment has passed, and no object changes — so a screen left open across that moment would go on showing the moon. This sleeps until the end date
/// and then stops drawing. The legacy screen does not: it reconfigures its bar on notifications, and none of them fires for a mute simply running out.
struct DiscussionUnmuteButton: View {

    let mute: DiscussionHeader.Mute
    let act: (DiscussionBarAction) -> Void

    /// Whether the mute is still running, as far as this view is concerned. It starts true — a `Mute` is only ever made for one that has not ended — and turns
    /// false when the end date arrives.
    @State private var isStillMuted = true

    var body: some View {
        // A `Group` and not a container: an item that has nothing to draw must take no space in the bar.
        Group {
            if isStillMuted {
                Menu {
                    // The sentence naming the end date is the menu's *header*, which is what `UIMenu(title:)` draws it as on the legacy screen.
                    Section {
                        Button { act(.unmute) } label: {
                            Label { Text("UNMUTE_NOTIFICATIONS") } icon: { Image(systemIcon: .moonZzzFill) }
                        }
                    } header: {
                        Text(verbatim: mute.sentence)
                    }
                } label: {
                    Image(systemIcon: .moonZzzFill)
                }
            }
        }
        .task(id: mute.endDate) { await stopsDrawingWhenTheMuteEnds() }
    }


    private func stopsDrawingWhenTheMuteEnds() async {
        isStillMuted = true
        let secondsLeft = mute.endDate.timeIntervalSinceNow
        // A mute set for ten years or more is what the app calls indefinite. Sleeping that long is harmless — the task dies with the screen — but there is no
        // reason to schedule it.
        guard secondsLeft > 0, secondsLeft < TimeInterval(years: 10) else { return }
        try? await Task.sleep(seconds: secondsLeft)
        guard !Task.isCancelled else { return }
        withAnimation { isStillMuted = false }
    }

}
