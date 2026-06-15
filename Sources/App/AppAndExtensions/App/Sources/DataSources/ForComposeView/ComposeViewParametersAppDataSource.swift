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
import Combine
import ObvComposition
import ObvSettings


@MainActor
final class ComposeViewParametersAppDataSource {
    
    private var composeViewParametersStreamManagerForStreamUUID: [UUID: ComposeViewParametersStreamManager] = [:]

}


// MARK: - Implementing

extension ComposeViewParametersAppDataSource: ComposeViewParametersDataSource {
    
    func getAsyncStreamOfComposeViewParameters(_ view: ObvComposition.ComposeView) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvComposition.ComposeViewParameters>) {
        let manager = ComposeViewParametersStreamManager()
        composeViewParametersStreamManagerForStreamUUID[manager.streamUUID] = manager
        return try manager.startStream()
    }
    
    func finishAsyncStreamOfComposeViewParameters(streamUUID: UUID) {
        if let manager = composeViewParametersStreamManagerForStreamUUID.removeValue(forKey: streamUUID) {
            manager.finishStream()
        }
    }
    
}


extension ComposeViewParametersAppDataSource {
    
    private final class ComposeViewParametersStreamManager {
        
        private var cancellables = Set<AnyCancellable>()
        let streamUUID = UUID()
        private var stream: AsyncStream<ObvComposition.ComposeViewParameters>?
        private var continuation: AsyncStream<ObvComposition.ComposeViewParameters>.Continuation?
        private var previouslyYieldedModel: ObvComposition.ComposeViewParameters?

        deinit {
            cancellables.forEach { $0.cancel() }
            cancellables.removeAll()
        }
        
        func startStream() throws -> (streamUUID: UUID, stream: AsyncStream<ObvComposition.ComposeViewParameters>) {
            if let stream {
                return (streamUUID, stream)
            }

            continuouslyObserveSettings()
            
            let stream = AsyncStream(ObvComposition.ComposeViewParameters.self) { [weak self] (continuation: AsyncStream<ObvComposition.ComposeViewParameters>.Continuation) in
                guard let self else { return }
                self.continuation = continuation
                let model = createModel()
                yieldModelIfNeeded(model: model)
            }
            self.stream = stream
            return (streamUUID, stream)
        }

        func finishStream() {
            continuation?.finish()
            continuation = nil
            cancellables.forEach({ $0.cancel() })
            cancellables.removeAll()
        }

        private func createModel() -> ObvComposition.ComposeViewParameters {
            let model = ComposeViewParameters(
                sortableActions: .init(ObvMessengerSettings.Interface.preferredComposeMessageViewActionsOrder),
                unsortableActions: .init(NewComposeMessageViewUnsortableAction.allCases),
                defaultEmojiButton: ObvMessengerSettings.Emoji.defaultEmojiButton ?? ObvMessengerConstants.defaultEmoji,
                sendMessageShortcutType: .init(ObvMessengerSettings.Interface.sendMessageShortcutType))
            return model
        }
        
        private func yieldModelIfNeeded(model: ObvComposition.ComposeViewParameters) {
            guard let continuation else { return }
            guard previouslyYieldedModel != model else { return }
            previouslyYieldedModel = model
            continuation.yield(model)
        }

        
        private func continuouslyObserveSettings() {
            
            ObvMessengerSettingsObservableObject.shared.$defaultEmojiButton
                .sink { [weak self] _ in
                    guard let self else { return }
                    let model = createModel()
                    yieldModelIfNeeded(model: model)
                }
                .store(in: &cancellables)
            
            ObvMessengerSettingsObservableObject.shared.$sendMessageShortcutType
                .sink { [weak self] newValue in
                    guard let self else { return }
                    let model = createModel()
                    yieldModelIfNeeded(model: model)
                }
                .store(in: &cancellables)
            
            ObvMessengerSettingsObservableObject.shared.$preferredComposeMessageViewActionsOrder
                .sink { [weak self] newValue in
                    guard let self else { return }
                    let model = createModel()
                    yieldModelIfNeeded(model: model)
                }
                .store(in: &cancellables)
            
        }
        
    }
    
}


// MARK: - Private helpers

extension ObvComposition.ComposeViewParameters.SortableAction {

    init(_ sortableAction: NewComposeMessageViewSortableAction) {
        switch sortableAction {
        case .oneTimeEphemeralMessage: self = .oneTimeEphemeralMessage
        case .scanDocument: self = .scanDocument
        case .shootPhotoOrMovie: self = .shootPhotoOrMovie
        case .chooseImageFromLibrary: self = .chooseImageFromLibrary
        case .choseFile: self = .choseFile
        case .introduceThisContact: self = .introduceThisContact
        case .shareLocation: self = .shareLocation
        case .createPoll: self = .createPoll
        case .pasteContent: self = .pasteContent
        }
    }
    
}


extension ObvComposition.ComposeViewParameters.UnsortableAction {
    
    init(_ unsortableAction: NewComposeMessageViewUnsortableAction) {
        switch unsortableAction {
        case .composeMessageSettings: self = .composeMessageSettings
        }
    }
    
}


extension [ObvComposition.ComposeViewParameters.SortableAction] {
    
    init(_ sortableActions: [NewComposeMessageViewSortableAction]) {
        self = sortableActions.map { .init($0) }
    }
    
}


extension [ObvComposition.ComposeViewParameters.UnsortableAction] {
    
    init(_ unsortableActions: [NewComposeMessageViewUnsortableAction]) {
        self = unsortableActions.map { .init($0) }
    }

}


extension ComposeViewParameters.SendMessageShortcutType {
    
    init(_ sendMessageShortcutType: ObvMessengerSettings.Interface.SendMessageShortcutType) {
        switch sendMessageShortcutType {
        case .enter: self = .enter
        case .commandEnter: self = .commandEnter
        }
    }
    
}
