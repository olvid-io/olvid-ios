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
import ObvDesignSystem
import ObvTypes


@MainActor
public protocol ObvTrustOriginsListViewDataSource {
    func getAsyncStreamOfObvTrustOriginsListViewModel(_ view: ObvTrustOriginsListView, contactIdentifier: ObvContactIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<ObvTrustOriginsListView.Model>)
    func finishAsyncStreamOfObvTrustOriginsListViewModel(_ view: ObvTrustOriginsListView, streamUUID: UUID)
}

public struct ObvTrustOriginsListView: View {

    let contactIdentifier: ObvContactIdentifier
    let dataSource: any ObvTrustOriginsListViewDataSource
    
    public init(contactIdentifier: ObvContactIdentifier, dataSource: any ObvTrustOriginsListViewDataSource) {
        self.contactIdentifier = contactIdentifier
        self.dataSource = dataSource
    }
    
    public struct Model {
        let trustOrigins: [ObvTrustOriginCellView.Model]
        
        public init(trustOrigins: [ObvTrustOriginCellView.Model]) {
            self.trustOrigins = trustOrigins
        }
        
    }
    
    @State private var model: Model?
    
    private func onTask() async {
        do {
            let (streamUUID, stream) = try dataSource.getAsyncStreamOfObvTrustOriginsListViewModel(self, contactIdentifier: contactIdentifier)
            for await receivedModel in stream {
                withAnimation {
                    self.model = receivedModel
                }
            }
            dataSource.finishAsyncStreamOfObvTrustOriginsListViewModel(self, streamUUID: streamUUID)
        } catch {
            assertionFailure()
        }
    }
    
    private var navigationTitle: String {
        String(localizedInThisBundle: "TRUST_ORIGINS")
    }
    
    public var body: some View {
        Group {
            if let model {
                ObvTrustOriginsListInternalView(model: model)
            } else {
                ObvCenteredProgressView()
            }
        }
        .navigationTitle(navigationTitle)
        .task(onTask)
    }
    
}


// MARK: - Internal view

private struct ObvTrustOriginsListInternalView: View {

    let model: ObvTrustOriginsListView.Model
    
    var body: some View {
        List {
            ForEach(model.trustOrigins, id: \.self) { trustOrigin in
                ObvTrustOriginCellView(model: trustOrigin)
            }
            .listStyle(.grouped)
        }
    }
    
}


#if DEBUG

// MARK: - Previews

@MainActor
private final class DataSourceForPreviews: ObvTrustOriginsListViewDataSource {
    
    func getAsyncStreamOfObvTrustOriginsListViewModel(_ view: ObvTrustOriginsListView, contactIdentifier: ObvTypes.ObvContactIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<ObvTrustOriginsListView.Model>) {
        let stream = AsyncStream<ObvTrustOriginsListView.Model> { (continuation: AsyncStream<ObvTrustOriginsListView.Model>.Continuation) in
            Task {
                try? await Task.sleep(seconds: 1)
                let model = ObvTrustOriginsListView.Model(trustOrigins: [
                    .init(contactIdentifier: .sampleData,
                          date: Date.now.addingTimeInterval(-10),
                          kind: .direct),
                    .init(contactIdentifier: .sampleData,
                          date: Date.now.addingTimeInterval(-100),
                          kind: .groupV1(groupOwner: .sampleData,
                                         groupOwnerName: "Group owner name")),
                    .init(contactIdentifier: .sampleData,
                          date: Date.now.addingTimeInterval(-1000),
                          kind: .groupV1(groupOwner: .sampleData,
                                         groupOwnerName: nil)),
                    .init(contactIdentifier: .sampleData,
                          date: Date.now.addingTimeInterval(-2000),
                          kind: .groupV2Server(groupIdentifier: .sampleData,
                                               groupName: "Group name")),
                    .init(contactIdentifier: .sampleData,
                          date: Date.now.addingTimeInterval(-3000),
                          kind: .groupV2Server(groupIdentifier: .sampleData,
                                               groupName: nil)),
                    .init(contactIdentifier: .sampleData,
                          date: Date.now.addingTimeInterval(-4000),
                          kind: .introduction(mediator: .sampleData,
                                              mediatorName: "Mediator name")),
                    .init(contactIdentifier: .sampleData,
                          date: Date.now.addingTimeInterval(-5000),
                          kind: .introduction(mediator: .sampleData,
                                              mediatorName: nil)),
                    .init(contactIdentifier: .sampleData,
                          date: Date.now.addingTimeInterval(-5000),
                          kind: .keycloak),
                ])
                continuation.yield(model)
            }
        }
        return (UUID(), stream)
    }
    
    func finishAsyncStreamOfObvTrustOriginsListViewModel(_ view: ObvTrustOriginsListView, streamUUID: UUID) {}
    
}


@MainActor
private let dataSourceForPreviews = DataSourceForPreviews()


#Preview {
    NavigationStack {
        ObvTrustOriginsListView(contactIdentifier: .sampleData,
                                dataSource: dataSourceForPreviews)
    }
}

#endif
