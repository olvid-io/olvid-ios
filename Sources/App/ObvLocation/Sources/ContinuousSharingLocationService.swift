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
import OSLog
import CoreLocation
import Combine
import CoreData
import ObvUICoreData
import ObvTypes
import ObvAppTypes
import ObvAppCoreConstants

@MainActor
public final class ContinuousSharingLocationService {
    
    //MARK: Singleton
    public static let shared = ContinuousSharingLocationService()

    //MARK: Last location shared
    private var lastSharedLocation: CLLocation?
    
    // If no location has been shared after a certain threshold, we just check that the location has not expired.
    private var pingTimer: Timer?
    
    private let pingTimeInterval = TimeInterval(minutes: 2) // We check every two minutes that the current location has not expired.
    
    // We do not want to send location updates if the current user does not move more than 10 meters.
    private let minDistanceBetweenLocations: CLLocationDistance = 10
    
    // We do not want to send location update if the last location has been sent less than 30 seconds ago.
    private let minTimeBetweenLocations: TimeInterval = 30
    
    private var isSharingLocationToDiscussion: Bool {
        !discussionsWhereLocationIsShared.isEmpty
    }
    
    private var cancellables: Set<AnyCancellable> = []
    
    /// We keep a set of discussions where we send our location continously
    private var discussionsWhereLocationIsShared = Set<ObvDiscussionIdentifier>()

    /// The maximum expiration date across all discussions (thus, across all profiles)
    private var currentExpirationDate: Date? = Date.distantPast // nil for endless sharing
    
    /// If we are sharing location to discussion, we don't want to stop it
    var continuousSharingLocationCanBeStopped: Bool {
        return !isSharingLocationToDiscussion
    }
    
    var isSharing: Bool {
        return isSharingLocationToDiscussion
    }
    
    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: ContinuousSharingLocationService.self))
    
    private var delegate: ContinuousSharingLocationServiceDelegate?
    
    init() {
        bind()
    }
    
    
    public func setDelegate(to newDelegate: ContinuousSharingLocationServiceDelegate) {
        self.delegate = newDelegate
    }
    
    
    private func bind() {
        ObvLocationService.shared.$location.sink { [weak self] location in
            guard let self else { return }
            Task { await self.locationUpdated(location) }
        }.store(in: &cancellables)
    }
    
    public func startSharingLocationToDiscussion(discussionIdentifier: ObvDiscussionIdentifier,
                                                 expirationDate: Date?) {
        
        guard let delegate else {
            Self.logger.fault("The delegate is nil")
            assertionFailure()
            return
        }

        // The new currentExpirationDate is the "max" between the old currentExpirationDate and the received expirationDate
        
        let distantFuture = Date.distantFuture
        self.currentExpirationDate = max(self.currentExpirationDate ?? .distantFuture, expirationDate ?? .distantFuture)
        if self.currentExpirationDate == distantFuture {
            self.currentExpirationDate = nil // means endless sharing
        }
        
        let currentLocation = ObvLocationService.shared.location ?? CLLocation(latitude: 0, longitude: 0)
        
        resetLocationPing()
        
        let locationData = ObvLocationData(clLocation: currentLocation)
        let obvLocation = ObvLocation.startSharing(locationData: locationData, discussionIdentifier: discussionIdentifier, expirationDate: expirationDate)
        
        Task { [weak self] in
            
            guard let self else { return }
            
            do {
                try await delegate.newObvLocationToProcessForThisPhysicalDevice(self, location: obvLocation)
            } catch {
                Self.logger.fault("Failed to update location: \(error)")
                assertionFailure()
                return
            }
            
            discussionsWhereLocationIsShared.insert(discussionIdentifier)

            /// We start location monitoring continuously if it was not already started
            /// If it was, it should just update the first location directly.
            do {
                try await ObvLocationService.shared.startMonitoringLocationContinuously()
            } catch {
                debugPrint("Error while sharing location continuously: \(error)")
                return
            }

        }

    }
    
    /// Stop Sharing location.
    /// Pass `nil` in order to stop location for every discussions
    public func stopSharingLocation(discussionIdentifier: ObvDiscussionIdentifier? = nil) async {
                
        stopLocation(discussionIdentifier: discussionIdentifier)
        
        if let discussionIdentifier {
            discussionsWhereLocationIsShared.remove(discussionIdentifier)
        } else {
            discussionsWhereLocationIsShared.removeAll()
        }
        
        if discussionsWhereLocationIsShared.isEmpty {
            await ObvLocationService.shared.stopUpdatingLocation()
            self.lastSharedLocation = nil
            self.currentExpirationDate = .distantPast
            self.pingTimer?.invalidate()
            self.pingTimer = nil
        }
        
    }
}

extension ContinuousSharingLocationService {
    
    private func resetLocationPing() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(timeInterval: pingTimeInterval, target: self, selector: #selector(pingLocation), userInfo: nil, repeats: true)
    }
    
    @objc
    private func pingLocation() {
        guard !discussionsWhereLocationIsShared.isEmpty else { return }
        if Date.now > (self.currentExpirationDate ?? .distantFuture) {
            Task {
                await stopSharingLocation()
            }
        }
    }
}

extension ContinuousSharingLocationService {
    
    private func locationUpdated(_ location: CLLocation?) async {
        guard let location, isNewLocationRelevant(location) else { return }
        
        await updateLocation(location: location)
        
        lastSharedLocation = location
        resetLocationPing()
    }
    
    /// Method to check is new location is relevant to be used, because it may not be far away enough from the previous point or it has been detected too early in comparison of the previous point
    private func isNewLocationRelevant(_ location: CLLocation) -> Bool {
        guard let previousLocation = lastSharedLocation else { return true }
        
        let previousTimestamp = previousLocation.timestamp
        let newTimestamp = location.timestamp
        let differenceInTime = newTimestamp.timeIntervalSince(previousTimestamp)
        let distance = location.distance(from: previousLocation)
        
        if distance < minDistanceBetweenLocations { return false }
        
        if differenceInTime < minTimeBetweenLocations { return false }
        
        return true
    }
}


// Mark: Extension in order to handle Datas
extension ContinuousSharingLocationService {
    
    private func updateLocation(location: CLLocation) async {
        
        let locationData = ObvLocationData(clLocation: location)
        let obvLocation = ObvLocation.updateSharing(locationData: locationData)
        
        guard let delegate else {
            Self.logger.fault("The delegate is nil")
            assertionFailure()
            return
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                try await delegate.newObvLocationToProcessForThisPhysicalDevice(self, location: obvLocation)
            } catch {
                Self.logger.fault("Failed to update location: \(error)")
                assertionFailure()
            }
        }

    }
    
    private func stopLocation(discussionIdentifier: ObvDiscussionIdentifier? = nil) {
        
        guard let delegate else {
            Self.logger.fault("The delegate is nil")
            assertionFailure()
            return
        }
        
        let endSharingType: ObvLocation.EndSharingDestination
        if let discussionIdentifier {
            endSharingType = .discussion(discussionIdentifier: discussionIdentifier)
        } else {
            endSharingType = .all
        }

        let obvLocation = ObvLocation.endSharing(type: endSharingType)

        Task { [weak self] in
            guard let self else { return }
            do {
                try await delegate.newObvLocationToProcessForThisPhysicalDevice(self, location: obvLocation)
            } catch {
                Self.logger.fault("Failed to update location: \(error)")
                assertionFailure()
            }
        }
        
    }
}


public protocol ContinuousSharingLocationServiceDelegate: AnyObject {
    func newObvLocationToProcessForThisPhysicalDevice(_ continuousSharingLocationService: ContinuousSharingLocationService, location: ObvLocation) async throws
}
