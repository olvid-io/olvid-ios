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
import Combine
import ObvDiscussionsList
import ObvSettings


@MainActor
final class TipCellViewAppDataSourceForListOfArchivedDiscussions {
    
    private var tipCellViewModelStreamManagerForStreamUUID: [UUID: TipCellViewModelStreamManager] = [:]
    
}


// MARK: - Implementing TipCellViewDataSource

extension TipCellViewAppDataSourceForListOfArchivedDiscussions: TipCellViewDataSource {
    
    func getAsyncStreamOfTipCellViewModel(_ view: ObvDiscussionsList.ObvDiscussionsListView) throws -> (streamUUID: UUID, stream: AsyncStream<ObvDiscussionsList.TipCellViewModel?>) {
        let manager = TipCellViewModelStreamManager()
        tipCellViewModelStreamManagerForStreamUUID[manager.streamUUID] = manager
        return try manager.startStream()
    }
    
    func finishAsyncStreamOfTipCellViewModel(_ view: ObvDiscussionsList.ObvDiscussionsListView, streamUUID: UUID) {
        if let manager = tipCellViewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) {
            manager.finishStream()
        }
    }
    
}


// MARK: - Internal managers

extension TipCellViewAppDataSourceForListOfArchivedDiscussions {
    
    @MainActor
    private final class TipCellViewModelStreamManager {
        
        let streamUUID = UUID()
        private var stream: AsyncStream<ObvDiscussionsList.TipCellViewModel?>?
        private var continuation: AsyncStream<ObvDiscussionsList.TipCellViewModel?>.Continuation?
        private var previouslyYieldedModel: ObvDiscussionsList.TipCellViewModel?

        private var cancellables = Set<AnyCancellable>()

        func startStream() throws -> (streamUUID: UUID, stream: AsyncStream<TipCellViewModel?>) {
            if let stream {
                return (streamUUID, stream)
            }
            continuouslyObserveSettings()
            let stream = AsyncStream(TipCellViewModel?.self) { [weak self] (continuation: AsyncStream<TipCellViewModel?>.Continuation) in
                guard let self else { return }
                self.continuation = continuation
                let model = createModel()
                yieldModelIfNeeded(model: model)
            }
            self.stream = stream
            return (streamUUID, stream)
        }
        
        private func continuouslyObserveSettings() {
            
            ObvMessengerSettingsObservableObject.shared.$unarchiveDiscussions
                .receive(on: OperationQueue.main)
                .sink { [weak self] newValue in
                    guard let self else { return }
                    let model = createModel()
                    yieldModelIfNeeded(model: model)
                }
                .store(in: &cancellables)
            
        }
        
        func finishStream() {
            continuation?.finish()
            cancellables.forEach({ $0.cancel() })
        }

        private func createModel() -> TipCellViewModel {
            return TipCellViewModel.archivedDiscussionsHelpMessage(discussionsAreUnarchivedAutomatically: ObvMessengerSettings.Discussions.unarchiveDiscussions)
        }
        
        private func yieldModelIfNeeded(model: TipCellViewModel?) {
            guard let continuation else { assertionFailure(); return }
            guard previouslyYieldedModel != model else { return }
            previouslyYieldedModel = model
            continuation.yield(model)
        }

    }
    
}
