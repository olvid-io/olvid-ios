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

import Foundation
import ObvTypes
import OlvidUtils

public final class ObvMetaManager: ObvErrorMaker {
    
    public static let errorDomain = "ObvMetaManager"
    
    // MARK: Init
    
    public init() {}
    
    // MARK: One instance variable per case of the `ObvEngineDelegateType` enum.
    
    public private(set) var backupDelegate: ObvBackupDelegate? {
        didSet {
            fulfillPreviouslyRegisteredManagersRequirements(ofType: .ObvBackupDelegate, with: backupDelegate)
        }
    }

    public private(set) var createContextDelegate: ObvCreateContextDelegate? {
        didSet {
            fulfillPreviouslyRegisteredManagersRequirements(ofType: .ObvCreateContextDelegate, with: createContextDelegate)
        }
    }
    
    public private(set) var networkPostDelegate: ObvNetworkPostDelegate? {
        didSet {
            fulfillPreviouslyRegisteredManagersRequirements(ofType: .ObvNetworkPostDelegate, with: networkPostDelegate)
        }
    }
    
    public private(set) var networkFetchDelegate: ObvNetworkFetchDelegate? {
        didSet {
            fulfillPreviouslyRegisteredManagersRequirements(ofType: .ObvNetworkFetchDelegate, with: networkFetchDelegate)
        }
    }
    
    public private(set) var solveChallengeDelegate: ObvSolveChallengeDelegate? {
        didSet {
            fulfillPreviouslyRegisteredManagersRequirements(ofType: .ObvSolveChallengeDelegate, with: solveChallengeDelegate)
        }
    }
    
    public private(set) var processDownloadedMessageDelegate: ObvProcessDownloadedMessageDelegate? {
        didSet {
            fulfillPreviouslyRegisteredManagersRequirements(ofType: .ObvProcessDownloadedMessageDelegate, with: processDownloadedMessageDelegate)
        }
    }
    
    public private(set) var channelDelegate: ObvChannelDelegate? {
        didSet {
            fulfillPreviouslyRegisteredManagersRequirements(ofType: .ObvChannelDelegate, with: channelDelegate)
        }
    }
    
    public private(set) var keyWrapperForIdentityDelegate: ObvKeyWrapperForIdentityDelegate? {
        didSet {
            fulfillPreviouslyRegisteredManagersRequirements(ofType: .ObvKeyWrapperForIdentityDelegate, with: keyWrapperForIdentityDelegate)
        }
    }
    
    public private(set) var protocolDelegate: ObvProtocolDelegate? {
        didSet {
            fulfillPreviouslyRegisteredManagersRequirements(ofType: .ObvProtocolDelegate, with: protocolDelegate)
        }
    }
    
    public private(set) var fullRatchetProtocolStarterDelegate: ObvFullRatchetProtocolStarterDelegate? {
        didSet {
            fulfillPreviouslyRegisteredManagersRequirements(ofType: .ObvFullRatchetProtocolStarterDelegate, with: fullRatchetProtocolStarterDelegate)
        }
    }
    
    public private(set) var identityDelegate: ObvIdentityDelegate? {
        didSet {
            fulfillPreviouslyRegisteredManagersRequirements(ofType: .ObvIdentityDelegate, with: identityDelegate)
        }
    }
    
    public private(set) var notificationDelegate: ObvNotificationDelegate? {
        didSet {
            fulfillPreviouslyRegisteredManagersRequirements(ofType: .ObvNotificationDelegate, with: notificationDelegate)
        }
    }
    
    public private(set) var flowDelegate: ObvFlowDelegate? {
        didSet {
            fulfillPreviouslyRegisteredManagersRequirements(ofType: .ObvFlowDelegate, with: flowDelegate)
        }
    }
    
    public private(set) var simpleFlowDelegate: ObvSimpleFlowDelegate? {
        didSet {
            fulfillPreviouslyRegisteredManagersRequirements(ofType: .ObvSimpleFlowDelegate, with: flowDelegate)
        }
    }

    // MARK: Provided vs. Required Requirements
    
    private var delegateRequirementsProvidedByTheRegisteredDelegates = Set<ObvEngineDelegateType>()
    private var delegateRequirementsOfRegisteredDelegates = Set<ObvEngineDelegateType>()
    
    public func ensureAllDelegateRequirementsAreSatisfied() throws {
        let unfulfilledDelegateRequirements = delegateRequirementsOfRegisteredDelegates.subtracting(delegateRequirementsProvidedByTheRegisteredDelegates)
        if !unfulfilledDelegateRequirements.isEmpty {
            unfulfilledDelegateRequirements.forEach {
                debugPrint("[ERROR] The following delegate is required but not provided: \($0)")
            }
            throw Self.makeError(message: "Unfulfilled delegate requirements")
        }
    }

    // MARK: List of managers for which we could not fulfill all delegate requirements (yet)
    
    private var managersWithUnfulfilledRequirements = [ObvEngineDelegateType: [ObvManager]]()
    
    private func fulfillPreviouslyRegisteredManagersRequirements(ofType delegateType: ObvEngineDelegateType, with manager: ObvManager?) {
        if let manager = manager {
            for managerWithRequirement in managersWithUnfulfilledRequirements[delegateType] ?? [] {
                try! managerWithRequirement.fulfill(requiredDelegate: manager, forDelegateType: delegateType)
            }
            managersWithUnfulfilledRequirements.removeValue(forKey: delegateType)
        }
    }
    
    // MARK: Registering a new manager
    
    public private(set) var registeredManagers = [ObvManager]()
    
    public func register(_ manager: ObvManager) throws {
        
        try instantiateDelegatesImplementedBy(manager)
        
        // A manager might have certain requirements. We fulfill all the requirements that we can fulfill now. The requirements that cannot be fulfilled now result in a new entry in `managersWithUnfulfilledRequirements`. We also register the data model of this manager.
        try fulfillRequirementsOf(manager)
        
        manager.requiredDelegates.forEach {
            delegateRequirementsOfRegisteredDelegates.insert($0)
        }
        
        registeredManagers.append(manager)
    }
    
    private func instantiateDelegatesImplementedBy(_ manager: ObvManager) throws {
        
        for possibleDelegateType in ObvEngineDelegateType.allCases {
            
            switch possibleDelegateType {
                
            case .ObvBackupDelegate:
                if let manager = manager as? ObvBackupDelegate {
                    guard backupDelegate == nil else {
                        throw Self.makeError(message: "Failed to instantiate delegate (ObvBackupDelegate)")
                    }
                    backupDelegate = manager
                    delegateRequirementsProvidedByTheRegisteredDelegates.insert(.ObvBackupDelegate)
                }
                
            case .ObvCreateContextDelegate:
                if let manager = manager as? ObvCreateContextDelegate {
                    guard createContextDelegate == nil else {
                        throw Self.makeError(message: "Failed to instantiate delegate (ObvCreateContextDelegate)")
                    }
                    createContextDelegate = manager
                    delegateRequirementsProvidedByTheRegisteredDelegates.insert(.ObvCreateContextDelegate)
                }
                
            case .ObvNetworkPostDelegate:
                if let manager = manager as? ObvNetworkPostDelegate {
                    guard networkPostDelegate == nil else {
                        throw Self.makeError(message: "Failed to instantiate delegate (ObvNetworkPostDelegate)")
                    }
                    networkPostDelegate = manager
                    delegateRequirementsProvidedByTheRegisteredDelegates.insert(.ObvNetworkPostDelegate)
                }
                
            case .ObvNetworkFetchDelegate:
                if let manager = manager as? ObvNetworkFetchDelegate {
                    guard networkFetchDelegate == nil else {
                        throw Self.makeError(message: "Failed to instantiate delegate (ObvNetworkFetchDelegate)")
                    }
                    networkFetchDelegate = manager
                    delegateRequirementsProvidedByTheRegisteredDelegates.insert(.ObvNetworkFetchDelegate)
                }
                
            case .ObvSolveChallengeDelegate:
                if let manager = manager as? ObvSolveChallengeDelegate {
                    guard solveChallengeDelegate == nil else {
                        throw Self.makeError(message: "Failed to instantiate delegate (ObvSolveChallengeDelegate)")
                    }
                    solveChallengeDelegate = manager
                    delegateRequirementsProvidedByTheRegisteredDelegates.insert(.ObvSolveChallengeDelegate)
                }
                
            case .ObvProcessDownloadedMessageDelegate:
                if let manager = manager as? ObvProcessDownloadedMessageDelegate {
                    guard processDownloadedMessageDelegate == nil else {
                        throw Self.makeError(message: "Failed to instantiate delegate (ObvProcessDownloadedMessageDelegate)")
                    }
                    processDownloadedMessageDelegate = manager
                    delegateRequirementsProvidedByTheRegisteredDelegates.insert(.ObvProcessDownloadedMessageDelegate)
                }
                
            case .ObvChannelDelegate:
                if let manager = manager as? ObvChannelDelegate {
                    guard channelDelegate == nil else {
                        throw Self.makeError(message: "Failed to instantiate delegate (ObvChannelDelegate)")
                    }
                    channelDelegate = manager
                    delegateRequirementsProvidedByTheRegisteredDelegates.insert(.ObvChannelDelegate)
                }
                
            case .ObvKeyWrapperForIdentityDelegate:
                if let manager = manager as? ObvKeyWrapperForIdentityDelegate {
                    guard keyWrapperForIdentityDelegate == nil else {
                        throw Self.makeError(message: "Failed to instantiate delegate (ObvKeyWrapperForIdentityDelegate)")
                    }
                    keyWrapperForIdentityDelegate = manager
                    delegateRequirementsProvidedByTheRegisteredDelegates.insert(.ObvKeyWrapperForIdentityDelegate)
                }
                
            case .ObvProtocolDelegate:
                if let manager = manager as? ObvProtocolDelegate {
                    guard protocolDelegate == nil else {
                        throw Self.makeError(message: "Failed to instantiate delegate (ObvProtocolDelegate)")
                    }
                    protocolDelegate = manager
                    delegateRequirementsProvidedByTheRegisteredDelegates.insert(.ObvProtocolDelegate)
                }
                
            case .ObvFullRatchetProtocolStarterDelegate:
                if let manager = manager as? ObvFullRatchetProtocolStarterDelegate {
                    guard fullRatchetProtocolStarterDelegate == nil else {
                        throw Self.makeError(message: "Failed to instantiate delegate (ObvFullRatchetProtocolStarterDelegate)")
                    }
                    fullRatchetProtocolStarterDelegate = manager
                    delegateRequirementsProvidedByTheRegisteredDelegates.insert(.ObvFullRatchetProtocolStarterDelegate)
                }
                
            case .ObvIdentityDelegate:
                if let manager = manager as? ObvIdentityDelegate {
                    guard identityDelegate == nil else {
                        throw Self.makeError(message: "Failed to instantiate delegate (ObvIdentityDelegate)")
                    }
                    identityDelegate = manager
                    delegateRequirementsProvidedByTheRegisteredDelegates.insert(.ObvIdentityDelegate)
                }
                
            case .ObvNotificationDelegate:
                if let manager = manager as? ObvNotificationDelegate {
                    guard notificationDelegate == nil else {
                        throw Self.makeError(message: "Failed to instantiate delegate (ObvNotificationDelegate)")
                    }
                    notificationDelegate = manager
                    delegateRequirementsProvidedByTheRegisteredDelegates.insert(.ObvNotificationDelegate)
                }
                
            case .ObvFlowDelegate:
                if let manager = manager as? ObvFlowDelegate {
                    guard flowDelegate == nil else {
                        throw Self.makeError(message: "Failed to instantiate delegate (ObvFlowDelegate)")
                    }
                    flowDelegate = manager
                    delegateRequirementsProvidedByTheRegisteredDelegates.insert(.ObvFlowDelegate)
                }

            case .ObvSimpleFlowDelegate:
                if let manager = manager as? ObvSimpleFlowDelegate {
                    guard simpleFlowDelegate == nil else {
                        throw Self.makeError(message: "Failed to instantiate delegate (ObvSimpleFlowDelegate)")
                    }
                    simpleFlowDelegate = manager
                    delegateRequirementsProvidedByTheRegisteredDelegates.insert(.ObvSimpleFlowDelegate)
                }
            }
        }
    }
    
    
    private func fulfillRequirementsOf(_ internalManager: ObvManager) throws {
        
        for requiredDelegate in internalManager.requiredDelegates {
            switch requiredDelegate {
                
            case .ObvBackupDelegate:
                let delegateType = ObvEngineDelegateType.ObvBackupDelegate
                if let delegate = backupDelegate {
                    try internalManager.fulfill(requiredDelegate: delegate, forDelegateType: delegateType)
                } else {
                    let otherManagers = managersWithUnfulfilledRequirements[delegateType] ?? [ObvManager]()
                    managersWithUnfulfilledRequirements[delegateType] = otherManagers + [internalManager]
                }

            case .ObvCreateContextDelegate:
                let delegateType = ObvEngineDelegateType.ObvCreateContextDelegate
                if let delegate = createContextDelegate {
                    try internalManager.fulfill(requiredDelegate: delegate, forDelegateType: delegateType)
                } else {
                    let otherManagers = managersWithUnfulfilledRequirements[delegateType] ?? [ObvManager]()
                    managersWithUnfulfilledRequirements[delegateType] = otherManagers + [internalManager]
                }
                
            case .ObvNetworkPostDelegate:
                let delegateType = ObvEngineDelegateType.ObvNetworkPostDelegate
                if let delegate = networkPostDelegate {
                    try internalManager.fulfill(requiredDelegate: delegate, forDelegateType: delegateType)
                } else {
                    let otherManagers = managersWithUnfulfilledRequirements[delegateType] ?? [ObvManager]()
                    managersWithUnfulfilledRequirements[delegateType] = otherManagers + [internalManager]
                }
                
            case .ObvNetworkFetchDelegate:
                let delegateType = ObvEngineDelegateType.ObvNetworkFetchDelegate
                if let delegate = networkFetchDelegate {
                    try internalManager.fulfill(requiredDelegate: delegate, forDelegateType: delegateType)
                } else {
                    let otherManagers = managersWithUnfulfilledRequirements[delegateType] ?? [ObvManager]()
                    managersWithUnfulfilledRequirements[delegateType] = otherManagers + [internalManager]
                }
                
            case .ObvSolveChallengeDelegate:
                let delegateType = ObvEngineDelegateType.ObvSolveChallengeDelegate
                if let delegate = solveChallengeDelegate {
                    try internalManager.fulfill(requiredDelegate: delegate, forDelegateType: delegateType)
                } else {
                    let otherManagers = managersWithUnfulfilledRequirements[delegateType] ?? [ObvManager]()
                    managersWithUnfulfilledRequirements[delegateType] = otherManagers + [internalManager]
                }
                
            case .ObvProcessDownloadedMessageDelegate:
                let delegateType = ObvEngineDelegateType.ObvProcessDownloadedMessageDelegate
                if let delegate = processDownloadedMessageDelegate {
                    try internalManager.fulfill(requiredDelegate: delegate, forDelegateType: delegateType)
                } else {
                    let otherManagers = managersWithUnfulfilledRequirements[delegateType] ?? [ObvManager]()
                    managersWithUnfulfilledRequirements[delegateType] = otherManagers + [internalManager]
                }
                
            case .ObvChannelDelegate:
                let delegateType = ObvEngineDelegateType.ObvChannelDelegate
                if let delegate = channelDelegate {
                    try internalManager.fulfill(requiredDelegate: delegate, forDelegateType: delegateType)
                } else {
                    let otherManagers = managersWithUnfulfilledRequirements[delegateType] ?? [ObvManager]()
                    managersWithUnfulfilledRequirements[delegateType] = otherManagers + [internalManager]
                }
                
            case .ObvKeyWrapperForIdentityDelegate:
                let delegateType = ObvEngineDelegateType.ObvKeyWrapperForIdentityDelegate
                if let delegate = keyWrapperForIdentityDelegate {
                    try internalManager.fulfill(requiredDelegate: delegate, forDelegateType: delegateType)
                } else {
                    let otherManagers = managersWithUnfulfilledRequirements[delegateType] ?? [ObvManager]()
                    managersWithUnfulfilledRequirements[delegateType] = otherManagers + [internalManager]
                }
                
            case .ObvProtocolDelegate:
                let delegateType = ObvEngineDelegateType.ObvProtocolDelegate
                if let delegate = protocolDelegate {
                    try internalManager.fulfill(requiredDelegate: delegate, forDelegateType: delegateType)
                } else {
                    let otherManagers = managersWithUnfulfilledRequirements[delegateType] ?? [ObvManager]()
                    managersWithUnfulfilledRequirements[delegateType] = otherManagers + [internalManager]
                }
                
            case .ObvFullRatchetProtocolStarterDelegate:
                let delegateType = ObvEngineDelegateType.ObvFullRatchetProtocolStarterDelegate
                if let delegate = fullRatchetProtocolStarterDelegate {
                    try internalManager.fulfill(requiredDelegate: delegate, forDelegateType: delegateType)
                } else {
                    let otherManagers = managersWithUnfulfilledRequirements[delegateType] ?? [ObvManager]()
                    managersWithUnfulfilledRequirements[delegateType] = otherManagers + [internalManager]
                }
                
            case .ObvIdentityDelegate:
                let delegateType = ObvEngineDelegateType.ObvIdentityDelegate
                if let delegate = identityDelegate {
                    try internalManager.fulfill(requiredDelegate: delegate, forDelegateType: delegateType)
                } else {
                    let otherManagers = managersWithUnfulfilledRequirements[delegateType] ?? [ObvManager]()
                    managersWithUnfulfilledRequirements[delegateType] = otherManagers + [internalManager]
                }
                                
            case .ObvNotificationDelegate:
                let delegateType = ObvEngineDelegateType.ObvNotificationDelegate
                if let delegate = notificationDelegate {
                    try internalManager.fulfill(requiredDelegate: delegate, forDelegateType: delegateType)
                } else {
                    let otherManagers = managersWithUnfulfilledRequirements[delegateType] ?? [ObvManager]()
                    managersWithUnfulfilledRequirements[delegateType] = otherManagers + [internalManager]
                }
                
            case .ObvFlowDelegate:
                let delegateType = ObvEngineDelegateType.ObvFlowDelegate
                if let delegate = flowDelegate {
                    try internalManager.fulfill(requiredDelegate: delegate, forDelegateType: delegateType)
                } else {
                    let otherManagers = managersWithUnfulfilledRequirements[delegateType] ?? [ObvManager]()
                    managersWithUnfulfilledRequirements[delegateType] = otherManagers + [internalManager]
                }
                
            case .ObvSimpleFlowDelegate:
                let delegateType = ObvEngineDelegateType.ObvSimpleFlowDelegate
                if let delegate = simpleFlowDelegate {
                    try internalManager.fulfill(requiredDelegate: delegate, forDelegateType: delegateType)
                } else {
                    let otherManagers = managersWithUnfulfilledRequirements[delegateType] ?? [ObvManager]()
                    managersWithUnfulfilledRequirements[delegateType] = otherManagers + [internalManager]
                }

            }
        }
    }
    
    // MARK: Finalizing the initialization
    
    public func initializationFinalized(flowId: FlowIdentifier, runningLog: RunningLogError) throws {
        try ensureAllDelegateRequirementsAreSatisfied()
        // We register all the backupable managers within the backup delegate
        let allBackupableManagers = registeredManagers.compactMap { $0 as? ObvBackupableManager }
        backupDelegate?.registerAllBackupableManagers(allBackupableManagers)
        // We give a chance to all managers to finalize their own initialization
        guard let contextDelegate = registeredManagers.filter({$0 is ObvCreateContextDelegate}).first else {
            throw ObvMetaManager.makeError(message: "Could not find create context delegate")
        }
        let otherRegisteredDelegates = registeredManagers.filter({!($0 is ObvCreateContextDelegate)})
        try contextDelegate.finalizeInitialization(flowId: flowId, runningLog: runningLog)
        try otherRegisteredDelegates.forEach {
            try $0.finalizeInitialization(flowId: flowId, runningLog: runningLog)
        }
    }

}
