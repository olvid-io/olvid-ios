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

import SwiftUI
import UniformTypeIdentifiers
import CoreData
import ObvSystemIcon


/// ComposeAttachmentsView contains a list of ComposeAttachmentView
/// 
public struct ComposeAttachmentsView: View {
    
    private var attachments: [ComposeAttachmentView.AttachmentIdentifier]
    private var sharedState: ComposeView.SharedState
    private let attachmentDataSource: any ComposeAttachmentViewDataSource
    
    /// Actions
    private let actions: any ComposeViewActions
    
    init(viewModel: ComposeView.SharedState,
         attachments: [ComposeAttachmentView.AttachmentIdentifier],
         attachmentDataSource: any ComposeAttachmentViewDataSource,
         actions: any ComposeViewActions) {
        self.attachments = attachments
        self.sharedState = viewModel
        self.attachmentDataSource = attachmentDataSource
        self.actions = actions
    }
    
    /// During the sending of a message, we hide the attachments to prevent an animation glitch.
    /// If, in production/practice, this results in even worse animations, we will discard this computed variable.
    private var attachmentsToShow: [ComposeAttachmentView.AttachmentIdentifier] {
        if sharedState.isPreventingEdition {
            return []
        } else {
            return attachments
        }
    }
    
    public var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .bottom, spacing: 6.0) {
                ForEach(Array(attachmentsToShow.enumerated()), id: \.element) { index, attachmentIdentifier in
                    Button(action: {
                        try? actions.userDidTapOnDraftFyleJoinWithHardLink(self, at: index)
                    }) {
                        ComposeAttachmentView(viewModel: sharedState,
                                              attachmentIdentifier: attachmentIdentifier,
                                              dataSource: attachmentDataSource,
                                              actions: actions)
                    }
                }
            }
            .padding(6.0)
        }
        .scrollIndicators(.hidden)
        .clipShape(UnevenRoundedRectangle(cornerRadii: RectangleCornerRadii(topLeading: sharedState.globalCornerRadius, topTrailing: sharedState.globalCornerRadius), style: .continuous))
    }
    
}


// MARK: - ComposeAttachmentView

public struct ComposeAttachmentView: View {
    
    private let viewModel: ComposeView.SharedState
    private let attachmentIdentifier: AttachmentIdentifier
    private let dataSource: ComposeAttachmentViewDataSource
    private let actions: any ComposeViewActions
    
    public enum AttachmentIdentifier: Equatable, Sendable, Hashable {
        case persistedDraftFyleJoinObjectID(NSManagedObjectID)
    }
    
    private let initialDataSourceViewModel: ComposeViewDataSourceFyleModel?
    @State private var streamedDataSourceViewModel: ComposeViewDataSourceFyleModel?
    private var dataSourceViewModel: ComposeViewDataSourceFyleModel? {
        streamedDataSourceViewModel ?? initialDataSourceViewModel
    }
    
    init(viewModel: ComposeView.SharedState,
         attachmentIdentifier: AttachmentIdentifier,
         dataSource: ComposeAttachmentViewDataSource,
         actions: any ComposeViewActions) {
        self.viewModel = viewModel
        self.attachmentIdentifier = attachmentIdentifier
        self.dataSource = dataSource
        self.actions = actions
        
        if let initialDataSourceModel = dataSource.getInitialComposeViewDataSourceFyleModel(attachmentIdentifier: attachmentIdentifier) {
            self.initialDataSourceViewModel = initialDataSourceModel
        } else {
            self.initialDataSourceViewModel = nil
        }
    }
    
    @ViewBuilder
    public var content: some View {
        if let dataSourceViewModel {
            ImageForAttachment(contentTypeAndImage: dataSourceViewModel.contentTypeAndImage, globalCornerRadius: viewModel.globalCornerRadius)
        } else {
            ZStack(alignment: .center) {
                RoundedRectangle(cornerRadius: viewModel.globalCornerRadius / 2.0, style: .continuous)
                    .fill(Color(uiColor: .systemGroupedBackground))
                
                ProgressView()
            }
            .frame(width: 80)
        }
    }
    
    public var body: some View {
        ZStack(alignment: .topTrailing) {
            
            content

            AsyncButton(action: {
                do {
                    try await actions.userWantsToDeleteDraftAttachment(self, attachmentIdentifier: attachmentIdentifier)
                } catch {
                    assertionFailure()
                }
            }) {
                Image(systemIcon: .xmark)
                    .font(.system(size: 10, weight: .bold))
                    .padding(2.0)
                    .animation(nil, value: streamedDataSourceViewModel)
                    .clipShape(Circle())
            }
            .buttonBorderShapeObv(.circle)
            .buttonStyleObv(style: .glassOrBorderedProminent)
            .padding(.top, 4)
            .padding(.trailing, 2)
        }
        .task(onTaskForAsyncStreamOfComposeViewDataSourceFyleModel)
    }
    
}


private struct ImageForAttachment: View {
    
    let contentTypeAndImage: ComposeViewDataSourceFyleModel.ContentTypeAndImage
    let globalCornerRadius: CGFloat
    
    private static func iconForType(_ type: UTType) -> ObvSystemIcon.SystemIcon {
        switch type {
        case .zip: return .rectangleCompressVertical
        default: return .paperclip
        }
    }

    var body: some View {
        if let uiImage = contentTypeAndImage.image {
            
            ZStack {
                
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: globalCornerRadius / 2.0, style: .continuous))

                switch self.contentTypeAndImage.contentType {
                case .video:
                    Image(systemIcon: .videoFill)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(uiColor: .systemBackground))
                            .padding(6)
                default:
                    EmptyView()
                }
            }
            
        } else {
            
            ZStack(alignment: .center) {
                RoundedRectangle(cornerRadius: globalCornerRadius / 2.0, style: .continuous)
                    .fill(Color.primary.opacity(0.1))
                Image(systemIcon: Self.iconForType(contentTypeAndImage.contentType))
            }
            .frame(width: 80)
            
        }
    }
    
}


extension ComposeAttachmentView {

    private func onTaskForAsyncStreamOfComposeViewDataSourceFyleModel() async {
        do {
            let (streamUUID, stream) = try await dataSource.getAsyncStreamOfComposeViewDataSourceFyleModel(attachmentIdentifier: attachmentIdentifier)
            for await receivedDataSourceViewModel in stream {
                withAnimation {
                    self.streamedDataSourceViewModel = receivedDataSourceViewModel
                }
            }
            dataSource.finishAsyncStreamOfComposeViewDataSourceFyleModel(streamUUID: streamUUID)
        } catch {
            assertionFailure()
        }
    }
    
}

