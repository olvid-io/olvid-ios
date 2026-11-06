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


/// `@unchecked Sendable` so that ``shared`` can be reached from any isolation: the observers are main-actor state,
/// and ``post(_:)``, the only `nonisolated` member, touches none of it.
@MainActor
public final class ObvDarwinNotificationCenter: @unchecked Sendable {

    nonisolated public static let shared = ObvDarwinNotificationCenter()


    /// `nonisolated` because `CFNotificationCenterPostNotification` is thread-safe, and a caller about to be
    /// suspended, such as a share extension going to the background, cannot wait for the main actor.
    nonisolated public func post(_ darwinNotificationName: String) {
        let name = CFNotificationName(darwinNotificationName as CFString)
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), name, nil, nil, true)
    }
    

    public func addObserver(_ observer: ObvDarwinNotificationObserver, forDarwinNotificationName darwinNotificationName: String) {
        if var currentObservers = observers[darwinNotificationName] {
            currentObservers.append(observer)
            observers[darwinNotificationName] = currentObservers
        } else {
            observers[darwinNotificationName] = [observer]
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                            Unmanaged.passUnretained(self).toOpaque(),
                                            Self.didReceiveDarwinNotificationToForwardToObservers,
                                            darwinNotificationName as CFString,
                                            nil,
                                            .deliverImmediately)
        }
    }

    
    // MARK: - Private
    
    nonisolated private init() {}

    private var observers = [String: [ObvDarwinNotificationObserver]]()

    private static let didReceiveDarwinNotificationToForwardToObservers: CFNotificationCallback = { _, _, name, _, _ in
        guard let notificationName = name?.rawValue as? String else { return }
        ObvDarwinNotificationCenter.shared.postNotificationToObserversForNotificationName(notificationName)
    }

    
    private func postNotificationToObserversForNotificationName(_ notificationName: String) {
        let observers = self.observers[notificationName] ?? []
        for observer in observers {
            Task { await observer.didReceiveDarwinNotification(notificationName) }
        }
    }

}


public protocol ObvDarwinNotificationObserver: Sendable {
    func didReceiveDarwinNotification(_ darwinNotificationName: String) async
}
