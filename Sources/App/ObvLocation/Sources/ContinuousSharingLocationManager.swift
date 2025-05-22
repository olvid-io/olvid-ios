/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import ObvTypes
import ObvAppTypes
import ObvAppCoreConstants


@MainActor
public protocol ContinuousSharingLocationManagerDataSource: AnyObject, Sendable {
    func getAsyncSequenceOfContinuousSharingLocationManagerModel() throws -> (streamUUID: UUID, stream: AsyncStream<ContinuousSharingLocationManagerModel>)
}

public struct ContinuousSharingLocationManagerModel: Sendable, Equatable {
    
    public enum ContinuousSharingLocationFromCurrentDeviceKind: Sendable, Equatable {
        case notSharingFromCurrentOwnedDevice
        case sharingFromCurrentOwnedDevice(maxExpiration: ObvLocationSharingExpirationDate)
    }
    
    let continuousSharingLocationFromCurrentDeviceKind: ContinuousSharingLocationFromCurrentDeviceKind

    public init(continuousSharingLocationFromCurrentDeviceKind: ContinuousSharingLocationFromCurrentDeviceKind) {
        self.continuousSharingLocationFromCurrentDeviceKind = continuousSharingLocationFromCurrentDeviceKind
    }
    
}


public actor ContinuousSharingLocationManager {

    private weak var datasource: ContinuousSharingLocationManagerDataSource?
    private weak var delegate: ContinuousSharingLocationManagerDelegate?

    /// True iff we were requested to start monitoring location updates. Set this to `false` to stop monitoring.
    private var shouldMonitorCLLocationUpdateLiveUpdates = false
    
    /// True iff we are currently monitoring location updates
    private var isCurrentlyMonitoringCLLocationUpdateLiveUpdates = false
    
    private let sentContinuousLocationRateLimiter = SentContinuousLocationRateLimiter()

    private var previousProcessedModel: ContinuousSharingLocationManagerModel?
    
    private var backgroundActivitySession: AnyObject? // In practice, a CLBackgroundActivitySession, which only available on iOS 17.0+
    
    @available(iOS 17.0, *)
    private func requestStreamFromDatasource() async {
        do {
            guard let datasource else { assertionFailure(); return }
            let (_, stream) = try await datasource.getAsyncSequenceOfContinuousSharingLocationManagerModel()
            for await model in stream {
                
                // Filter out the new model if it is identical to the model that was previously taken into account
                guard model != previousProcessedModel else { continue }
                previousProcessedModel = model
                
                switch model.continuousSharingLocationFromCurrentDeviceKind {
                case .notSharingFromCurrentOwnedDevice:
                    await stopSharingLocation()
                case .sharingFromCurrentOwnedDevice(maxExpiration: let maxExpiration):
                    await startOrContinueSharingLocation(maxExpirationDate: maxExpiration)
                }
                
            }
        } catch {
            Self.logger.fault("Could not obtain stream from datasource: \(error.localizedDescription)")
            assertionFailure()
        }
    }
    
    /// The maximum expiration date across all discussions (thus, across all profiles)
    private var maxExpirationDate: ObvLocationSharingExpirationDate? // nil when not sharing location (or at startup, until we receive the first model from the stream)
    
    
    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: ContinuousSharingLocationManager.self))
    
    
    
    public init() {}
    
    public func setDelegateAndDatasource(delegate newDelegate: ContinuousSharingLocationManagerDelegate, datasource: ContinuousSharingLocationManagerDataSource) {
        assert(self.delegate == nil, "This method is expected to be called only once")
        assert(self.datasource == nil, "This method is expected to be called only once")
        self.delegate = newDelegate
        self.datasource = datasource
        if #available(iOS 17.0, *) {
            Task {
                await requestStreamFromDatasource()
            }
        }
    }

    
    /// This method is called when the user starts sharing her location in a discussion.
    @available(iOS 17.0, *)
    private func startOrContinueSharingLocation(maxExpirationDate: ObvLocationSharingExpirationDate) async {

        self.maxExpirationDate = maxExpirationDate
        
        shouldMonitorCLLocationUpdateLiveUpdates = true
        
        Task {
            
            guard !isCurrentlyMonitoringCLLocationUpdateLiveUpdates else {
                Self.logger.info("No need to start monitoring location continuously as it is already running")
                return
            }
            
            isCurrentlyMonitoringCLLocationUpdateLiveUpdates = true
            defer { isCurrentlyMonitoringCLLocationUpdateLiveUpdates = false }

            var count = 0
            
            do {
                
                Self.logger.debug("Creating (or re-creating) a CLBackgroundActivitySession")
                self.backgroundActivitySession = CLBackgroundActivitySession()
                
                Self.logger.debug("Calling CLLocationUpdate.liveUpdates()")
                let updates = CLLocationUpdate.liveUpdates()
                
                for try await update in updates {
                    
                    count += 1
                    
                    if !self.shouldMonitorCLLocationUpdateLiveUpdates { break }  // End location updates by breaking out of the loop.
                    
                    guard let delegate else { assertionFailure(); continue }
                    guard let clLocation = update.location else {
                        Self.logger.warning("The CLLocationUpdate did not contain a location: isStationary: \(update.isStationary)")
                        continue
                    }
                    
                    Self.logger.debug("Location \(count): \(clLocation)")

                    // Make sure we did not exceed the maximum expiration date
                    
                    let shouldEndSharing: Bool
                    if let maxExpirationDate = self.maxExpirationDate {
                        switch maxExpirationDate {
                        case .never:
                            shouldEndSharing = false
                        case .after(let date):
                            shouldEndSharing = Date.now > date
                        }
                    } else {
                        shouldEndSharing = false
                    }
                    
                    let obvLocation: ObvLocation
                    if shouldEndSharing {
                        Self.logger.info("Will end sharing")
                        obvLocation = ObvLocation.endSharing(type: .all)
                        // We don't break out of the loop. We inform our delegate that the continuous sharing should stop.
                        // We will eventually be called back, thanks to our datasource, and stop the monitoring.
                    } else {
                        let locationData = ObvLocationData(clLocation: clLocation, isStationary: update.isStationary)
                        let decision = await self.sentContinuousLocationRateLimiter.determineSentContinuousLocationDecision(for: locationData)
                        switch decision {
                        case .doNotSend:
                            Self.logger.debug("Although a new location is available, we don't send it. Data was: longitude: \(locationData.longitude), latitude: \(locationData.latitude), isStationary: \(locationData.isStationary)")
                            continue // We loop and await the next location update
                        case .send:
                            Self.logger.info("Will update continous location shared from the current owned device with the following updated data: longitude: \(locationData.longitude), latitude: \(locationData.latitude), isStationary: \(locationData.isStationary)")
                            obvLocation = ObvLocation.updateSharing(locationData: locationData)
                        }
                    }
                    
                    Task { await delegate.newObvLocationToProcessForThisPhysicalDevice(self, location: obvLocation) }
                    
                }
            } catch {
                Self.logger.error("Could not start location updates: \(error.localizedDescription)")
            }
            
        }

    }

    /// Stop Sharing location.
    @available(iOS 17.0, *)
    private func stopSharingLocation() async {
        Self.logger.info("Stopping continuous location sharing")
        shouldMonitorCLLocationUpdateLiveUpdates = false
        (self.backgroundActivitySession as? CLBackgroundActivitySession)?.invalidate()
        self.backgroundActivitySession = nil
        await sentContinuousLocationRateLimiter.reset()
    }
    
}


/// When a continous location sharing from the current device is ongoing, we send the CoreLocation updates to our delegate (so it can send a new location update
/// message to our contacts).
///
/// Since `CLLocationUpdate.liveUpdates()` can produces location updates at a high rate, we do not notify our delegate for each of them, since we want to
/// limit the number of messages sent.
///
/// Instead, we filter the location updates according to following criterias:
/// - If the device is stationary, we send the location (according to Apple's documentation, no further updates will be received from `CLLocationUpdate.liveUpdates()`, unless the device moves again).
/// - If the location is not stationary:
///     - If a location was recently sent, we don't send the new one.
///     - If no location was recently sent, we send the new one.
fileprivate actor SentContinuousLocationRateLimiter {
    
    private let timeIntervalLimit: TimeInterval = 30 // seconds
    private var lastSentLocationDate: Date = .distantPast

    enum SentContinuousLocationDecision {
        case doNotSend
        case send
    }
    
    func reset() {
        lastSentLocationDate = .distantPast
    }
    
    func determineSentContinuousLocationDecision(for locationData: ObvLocationData) -> SentContinuousLocationDecision {
        
        let decision: SentContinuousLocationDecision
        
        if locationData.isStationary {
            decision = .send
        } else {
            let timeIntervalSinceLastSentLocation = Date.now.timeIntervalSince(lastSentLocationDate)
            assert(timeIntervalSinceLastSentLocation > 0)
            if timeIntervalSinceLastSentLocation < timeIntervalLimit {
                decision = .doNotSend
            } else {
                decision = .send
            }
        }
        
        if decision == .send {
            lastSentLocationDate = Date.now
        }
        
        return decision
        
    }
    
}



public protocol ContinuousSharingLocationManagerDelegate: AnyObject {
    func newObvLocationToProcessForThisPhysicalDevice(_ continuousSharingLocationManager: ContinuousSharingLocationManager, location: ObvLocation) async
}


@available(iOS 17.0, *)
extension ContinuousSharingLocationManager {
    
    enum ObvError: Error {
        case theDelegateIsNil
    }
    
}
