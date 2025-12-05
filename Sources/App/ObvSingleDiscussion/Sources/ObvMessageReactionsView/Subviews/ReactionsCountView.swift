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

import SwiftUI
import CoreData


// MARK: - ReactionsCountView's Model

public struct ObvReactionsCountViewModel: Equatable, Sendable {
    
    let reactionsAndCount: [ReactionAndCount]
    
    public init(reactionsAndCount: [ReactionAndCount]) {
        self.reactionsAndCount = reactionsAndCount.sorted()
    }
        
    public struct ReactionAndCount: Identifiable, Comparable, Sendable {
        
        let emoji: Character
        let count: Int
        
        public init(emoji: Character, count: Int) {
            self.emoji = emoji
            self.count = count
        }
        
        public var id: Character { emoji }
        
        public static func < (lhs: ObvReactionsCountViewModel.ReactionAndCount, rhs: ObvReactionsCountViewModel.ReactionAndCount) -> Bool {
            if lhs.count != rhs.count {
                return lhs.count > rhs.count
            } else {
                return lhs.emoji < rhs.emoji
            }
        }

    }
    
    static func emptyModel() -> Self {
        .init(reactionsAndCount: [])
    }
    
}


// MARK: - ReactionsCountView's data source

@MainActor
public protocol ReactionsCountViewDataSource: AnyObject {
    func getAsyncStreamOfReactionsCountViewModel(messageIdentifier: ObvMessageReactionsViewModel.MessageIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvReactionsCountViewModel>)
    func finishAsyncStreamOfReactionsCountViewModel(streamUUID: UUID)
}


// MARK: - ReactionsCountView

struct ReactionsCountView: View {
    
    let messageIdentifier: ObvMessageReactionsViewModel.MessageIdentifier
    let dataSource: ReactionsCountViewDataSource

    @State private var viewModel: ObvReactionsCountViewModel = .emptyModel()

    
    private func onTask() async {
        do {
            let (streamUUID, stream) = try await dataSource.getAsyncStreamOfReactionsCountViewModel(messageIdentifier: messageIdentifier)
            for await receivedModel in stream {
                withAnimation {
                    self.viewModel = receivedModel
                }
            }
            dataSource.finishAsyncStreamOfReactionsCountViewModel(streamUUID: streamUUID)
        } catch {
            assertionFailure()
        }
    }
    
    
    var body: some View {
        ReactionsCountContentView(viewModel: viewModel)
            .task(onTask)
    }
    
}


// MARK: - Internal view: ReactionsCountContentView

private struct ReactionsCountContentView: View {
    
    let viewModel: ObvReactionsCountViewModel
    
    var body: some View {
        HStack {
            ForEach(viewModel.reactionsAndCount) { reactionAndCount in
                HStack(alignment: .firstTextBaseline, spacing: 2.0) {
                    Text(String(reactionAndCount.emoji))
                    Text(String(reactionAndCount.count))
                        .monospacedDigit()
                        .contentTransitionOniOS16(.numericText(value: Double(reactionAndCount.count)))
                        .font(.caption.bold())
                        .lineLimit(1)
                        .transition(.scale.animation(.easeInOut(duration: 0.15)))
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical)
    }
    
}




#if DEBUG

private final class ReactionsCountViewDataSourceForPreviews: ReactionsCountViewDataSource {
    
    func getAsyncStreamOfReactionsCountViewModel(messageIdentifier: ObvMessageReactionsViewModel.MessageIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<ObvReactionsCountViewModel>) {
        let stream = AsyncStream { (continuation: AsyncStream<ObvReactionsCountViewModel>.Continuation) in
            Task {
                let model = ObvReactionsCountViewModel.sampleData
                continuation.yield(model)
            }
        }
        return (UUID(), stream)
    }
    
    func finishAsyncStreamOfReactionsCountViewModel(streamUUID: UUID) {
        // Nothing to finish in previews
    }
    
}


@MainActor
private let dataSourceForPreviews = ReactionsCountViewDataSourceForPreviews()


private struct PreviewView: View {
    
    let messageIdentifier: ObvMessageReactionsViewModel.MessageIdentifier
    let dataSource: ReactionsCountViewDataSource

    var body: some View {
        ZStack {
            Color(UIColor.systemBackground).ignoresSafeArea()
            VStack {
                Color.blue
                if #available(iOS 16, *) {
                    ViewThatFits {
                        ReactionsCountView(messageIdentifier: messageIdentifier,
                                           dataSource: dataSource)
                        ScrollView(.horizontal) {
                            ReactionsCountView(messageIdentifier: messageIdentifier,
                                               dataSource: dataSource)
                        }
                    }
                } else {
                    ScrollView(.horizontal) {
                        ReactionsCountView(messageIdentifier: messageIdentifier,
                                           dataSource: dataSource)
                    }
                }
            }
        }
    }
}


#Preview {
    PreviewView(messageIdentifier: .forPreview(UUID()), dataSource: dataSourceForPreviews)
}


#endif
