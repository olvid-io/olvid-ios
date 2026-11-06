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
import OSLog
import ObvTypes


/// Keeps the most recent server-request timings, so that a reader who reports "it takes ten seconds before I see a message" can send us measurements.
///
/// **On disk rather than in memory**: the reader notices the delay and looks at the diagnostics screen some time later, often after a relaunch. Held in
/// memory we would lose exactly the episode being complained about.
///
/// **In the shared defaults**, keyed on the container identifier the manager already has. A hundred timings is around twenty kilobytes — a tenth of a percent
/// of the notification extension's budget — so the limit is about keeping the report readable, not about memory. If thousands are ever wanted, use a file of
/// our own rather than a much bigger defaults key.
///
/// **Only the main app writes here**, the extensions' fetch managers doing no listing, so two processes never read-modify-write this array at once. If that
/// changes, this needs to be something better than a defaults key: interleaved writes would silently drop timings.
actor ServerRequestTimingStore {

    private static let logger = Logger(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: "ServerRequestTimingStore")

    private static let maximumNumberOfTimingsKeptPerRequest = 100

    private let userDefaults: UserDefaults?

    /// Held rather than made per call. Only the encoder is on the recording path; the decoder runs when a kind of request is read for the first time,
    /// and then not again — see ``cachedTimings``.
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// The decoded timings, per kind of request, in the order the defaults array holds them. Filled on the first read and kept in step by ``record(_:)``.
    ///
    /// **A cache is sound here only because of the invariant written at the top of this type**: the main app is the only writer, so nothing can change the
    /// defaults behind us. If that ever stops being true, this has to go with the rest of it.
    ///
    /// It exists because the drain polls ``howLongTheListingHasBeenUnableToReachTheServer`` once a second for up to half an hour, and decoding all hundred
    /// entries per poll would answer a question that changes only when a listing attempt is recorded, seconds to minutes apart.
    private var cachedTimings = [ObvServerRequestTiming.ServerRequest: [ObvServerRequestTiming]]()

    init(sharedContainerIdentifier: String) {
        self.userDefaults = UserDefaults(suiteName: sharedContainerIdentifier)
        if self.userDefaults == nil {
            Self.logger.fault("Could not open the shared user defaults, server request timings will not be recorded")
            assertionFailure()
        }
    }


    /// One key per kind of request, holding an array of separately encoded timings.
    ///
    /// Both halves of that matter. **A key per kind** means keeping the last hundred of each is a `suffix` on an array and needs no decoding — where a
    /// single key holding every kind would have to be decoded on each recording just to discover which entries to drop. And **separately encoded entries**
    /// mean appending one costs encoding one, rather than decoding the ninety-nine already there and encoding a hundred.
    private static func userDefaultsKey(for request: ObvServerRequestTiming.ServerRequest) -> String {
        "io.olvid.engine.networkFetch.serverRequestTimings.\(request.rawValue)"
    }


    func record(_ timing: ObvServerRequestTiming) {
        guard let userDefaults else { return }
        let key = Self.userDefaultsKey(for: timing.request)
        do {
            let encodedTiming = try encoder.encode(timing)
            // Read before the write, so the cache is brought forward from what was stored rather than from what we are about to store.
            let previous = storedTimings(for: timing.request)
            var encodedTimings = (userDefaults.array(forKey: key) as? [Data]) ?? []
            encodedTimings.append(encodedTiming)
            userDefaults.set(Array(encodedTimings.suffix(Self.maximumNumberOfTimingsKeptPerRequest)), forKey: key)
            cachedTimings[timing.request] = Array((previous + [timing]).suffix(Self.maximumNumberOfTimingsKeptPerRequest))
        } catch {
            Self.logger.fault("Could not encode a server request timing: \(error.localizedDescription)")
            assertionFailure()
        }
    }


    /// The timings we hold for the given request, oldest first.
    ///
    /// Sorted by their own date rather than trusted to be stored in order: recordings are made without waiting for them to land, so two made close together
    /// can be stored the other way round.
    func timings(for request: ObvServerRequestTiming.ServerRequest) -> [ObvServerRequestTiming] {
        storedTimings(for: request).sorted { $0.date < $1.date }
    }


    /// The timings we hold for the given request, in the order the defaults array holds them, decoding them only the first time they are asked for.
    ///
    /// An entry that cannot be decoded is dropped here, so this can be shorter than the stored array. That is why ``record(_:)`` keeps the cache by
    /// appending to what this returned rather than by counting: the two windows then agree on everything that is readable, which is everything anybody
    /// sees.
    private func storedTimings(for request: ObvServerRequestTiming.ServerRequest) -> [ObvServerRequestTiming] {
        if let cachedTimings = cachedTimings[request] { return cachedTimings }
        guard let userDefaults else { return [] }
        let encodedTimings = (userDefaults.array(forKey: Self.userDefaultsKey(for: request)) as? [Data]) ?? []
        let timings = encodedTimings.compactMap { try? decoder.decode(ObvServerRequestTiming.self, from: $0) }
        if timings.count != encodedTimings.count {
            // Said out loud rather than swallowed: an entry we cannot read and an entry that was never recorded look identical in the report otherwise.
            Self.logger.error("Could not decode \(encodedTimings.count - timings.count) of the \(encodedTimings.count) stored timings for \(request.rawValue)")
        }
        cachedTimings[request] = timings
        return timings
    }


    /// How long the listing has been failing to reach the server, counting only what happened since `since`, or nil if it is reaching it.
    ///
    /// A duration rather than a count: a caller polling once a second and a listing backing off over 5, 15, 30 and 60 seconds have no common unit, so a
    /// count of rounds means whatever the poll interval happens to be.
    ///
    /// Bounded by `since`, because a stale failure is not a current one: a device that was offline yesterday still holds those timings, and answering from
    /// them would stop a run whose first attempt has not yet come back. Such a run gets nil, *nothing known*, which lets it carry on.
    ///
    /// Measured from the first failure of the unbroken run of them that reaches the present, so it says how long the trouble has lasted rather than how
    /// old the last attempt is; the two differ by a whole back-off.
    func howLongTheListingHasBeenUnableToReachTheServer(since: Date, now: Date) -> TimeInterval? {
        ObvServerRequestTiming.howLongTheRequestsHaveBeenUnableToReachTheServer(
            in: timings(for: .downloadMessagesAndListAttachments),
            since: since,
            now: now)
    }

}
