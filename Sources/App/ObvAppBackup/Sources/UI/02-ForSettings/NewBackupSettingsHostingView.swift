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

import UIKit
import SwiftUI


protocol NewBackupSettingsHostingViewDelegate: AnyObject {
    @MainActor func userWantsToNavigateToNavigateToSecuritySettings(_ vc: NewBackupSettingsHostingView)
    @MainActor func userWantsToNavigateToManageBackups(_ vc: NewBackupSettingsHostingView)
    @MainActor func userWantsToSubscribeOlvidPlus(_ vc: NewBackupSettingsHostingView)
    @MainActor func userWantsToAddDevice(_ vc: NewBackupSettingsHostingView)
    @MainActor func usersWantsToGetBackupParameterIsSynchronizedWithICloud(_ vc: NewBackupSettingsHostingView) async throws -> Bool
    @MainActor func usersWantsToChangeBackupParameterIsSynchronizedWithICloud(_ vc: NewBackupSettingsHostingView, newIsSynchronizedWithICloud: Bool) async throws
    @MainActor func userWantsToPerformABackupNow(_ vc: NewBackupSettingsHostingView) async throws
}


final class NewBackupSettingsHostingView: UIHostingController<NewBackupSettingsView> {
    
    private let actions = ViewActions()
    private weak var internalDelegate: NewBackupSettingsHostingViewDelegate?
    
    init(subscriptionStatus: ObvSubscriptionStatusForAppBackup, delegate: NewBackupSettingsHostingViewDelegate) {
        let rootView = NewBackupSettingsView(subscriptionStatus: subscriptionStatus, actions: actions)
        super.init(rootView: rootView)
        self.internalDelegate = delegate
        actions.delegate = self
    }
    
    @MainActor @preconcurrency required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}


// MARK: - Implementing NewBackupSettingsViewActionsProtocol

extension NewBackupSettingsHostingView: NewBackupSettingsViewActionsProtocol {
    
    func userWantsToNavigateToNavigateToSecuritySettings() {
        internalDelegate?.userWantsToNavigateToNavigateToSecuritySettings(self)
    }
    
    func userWantsToNavigateToManageBackups() {
        internalDelegate?.userWantsToNavigateToManageBackups(self)
    }
    
    func userWantsToSubscribeOlvidPlus() {
        internalDelegate?.userWantsToSubscribeOlvidPlus(self)
    }

    func userWantsToAddDevice() {
        internalDelegate?.userWantsToAddDevice(self)
    }

    func usersWantsToGetBackupParameterIsSynchronizedWithICloud() async throws -> Bool {
        guard let internalDelegate else {
            assertionFailure()
            throw ObvError.delegateIsNil
        }
        return try await internalDelegate.usersWantsToGetBackupParameterIsSynchronizedWithICloud(self)
    }
    
    func usersWantsToChangeBackupParameterIsSynchronizedWithICloud(newIsSynchronizedWithICloud: Bool) async throws {
        try await internalDelegate?.usersWantsToChangeBackupParameterIsSynchronizedWithICloud(self, newIsSynchronizedWithICloud: newIsSynchronizedWithICloud)
    }

    func userWantsToPerformABackupNow() async throws {
        try await internalDelegate?.userWantsToPerformABackupNow(self)
    }

}


// MARK: - Errors

extension NewBackupSettingsHostingView {
    
    enum ObvError: Error {
        case delegateIsNil
    }

}


// MARK: - View's actions

@MainActor
private final class ViewActions: NewBackupSettingsViewActionsProtocol {
    
    weak var delegate: NewBackupSettingsViewActionsProtocol?
    
    func userWantsToNavigateToNavigateToSecuritySettings() {
        delegate?.userWantsToNavigateToNavigateToSecuritySettings()
    }
    
    func userWantsToNavigateToManageBackups() {
        delegate?.userWantsToNavigateToManageBackups()
    }
    
    func userWantsToSubscribeOlvidPlus() {
        delegate?.userWantsToSubscribeOlvidPlus()
    }
    
    func userWantsToAddDevice() {
        delegate?.userWantsToAddDevice()
    }
    
    func usersWantsToGetBackupParameterIsSynchronizedWithICloud() async throws -> Bool {
        guard let delegate else {
            assertionFailure()
            throw ObvError.delegateIsNil
        }
        return try await delegate.usersWantsToGetBackupParameterIsSynchronizedWithICloud()
    }
    
    func usersWantsToChangeBackupParameterIsSynchronizedWithICloud(newIsSynchronizedWithICloud: Bool) async throws {
        try await delegate?.usersWantsToChangeBackupParameterIsSynchronizedWithICloud(newIsSynchronizedWithICloud: newIsSynchronizedWithICloud)
    }
    
    
    func userWantsToPerformABackupNow() async throws {
        try await delegate?.userWantsToPerformABackupNow()
    }


    enum ObvError: Error {
        case delegateIsNil
    }

}
