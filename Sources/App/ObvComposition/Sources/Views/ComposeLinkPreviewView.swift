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
import CoreData
import ObvDesignSystem


@MainActor
public protocol ComposeLinkPreviewViewActions {
    func userWantsToDeleteDraftAttachment(_ view: ComposeLinkPreviewView, attachmentIdentifier: ComposeAttachmentView.AttachmentIdentifier) async throws
}


public struct ComposeLinkPreviewView: View {
    
    private let linkPreviewIdentifier: ComposeAttachmentView.AttachmentIdentifier
    private let dataSource: any ComposeLinkPreviewViewDataSource
    private let actions: any ComposeLinkPreviewViewActions
    
    @State private var viewModel: Model?
    
    public struct Model: Sendable, Equatable {
        let image: UIImage?
        let title: String?
        let desc: String?
        let url: URL?
        public init(image: UIImage?, title: String?, desc: String?, url: URL?) {
            self.image = image
            self.title = title
            self.desc = desc
            self.url = url
        }
    }

    init(linkPreviewIdentifier: ComposeAttachmentView.AttachmentIdentifier,
         dataSource: any ComposeLinkPreviewViewDataSource,
         actions: any ComposeLinkPreviewViewActions) {
        self.linkPreviewIdentifier = linkPreviewIdentifier
        self.dataSource = dataSource
        self.actions = actions
        self.viewModel = nil
    }
    
    @ViewBuilder
    var content: some View {
        Group {
            
            VStack(alignment: .leading) {
                
                HStack(alignment: .center) {
                    
                    HStack(alignment: .center, spacing: 8.0) {
                        
                        IconView(uiImage: viewModel?.image)
                        
                        ZStack {
                            
                            HStack {
                                if let viewModel {
                                    TextsView(style: .show(title: viewModel.title, desc: viewModel.desc, url: viewModel.url))
                                } else {
                                    TextsView(style: .hide)
                                }
                                Spacer(minLength: 0)
                            }
                            
                            HorizontalyCenteredProgressView()
                                .opacity(viewModel == nil ? 1.0 : 0.0)

                        }
                        
                    }
                    
                    Spacer()
                    
                    AsyncButton(
                        action: {
                            do {
                                try await self.actions.userWantsToDeleteDraftAttachment(self, attachmentIdentifier: linkPreviewIdentifier)
                            } catch {
                                assertionFailure()
                            }
                        }, label: {
                            Image(systemIcon: .trashFill)
                                .imageScale(.small)
                                .frame(width: 30, height: 30)
                                .clipShape(Circle())
                        })
                    .buttonBorderShapeObv(.circle)
                    .buttonStyleObv(style: .glassOrBordered)
                    .opacity(viewModel == nil ? 0.0 : 1.0)
                }
                .padding(.top, 6.0)
                
                Divider()
                
            }

        }
        .padding(.horizontal, 12.0)
        .clipped()
    }
    
    public var body: some View {
        content
            .task(id: linkPreviewIdentifier, onTaskForAsyncStreamOfComposeViewDataSourceFyleModel)
    }
    
}


extension ComposeLinkPreviewView {

    private func onTaskForAsyncStreamOfComposeViewDataSourceFyleModel() async {
        do {
            let (streamUUID, stream) = try await dataSource.getAsyncStreamOfComposeLinkPreviewViewModel(self, attachmentIdentifier: linkPreviewIdentifier)
            for await receivedDataSourceViewModel in stream {
                self.viewModel = receivedDataSourceViewModel
            }
            dataSource.finishAsyncStreamOfComposeLinkPreviewViewModel(self, streamUUID: streamUUID)
        } catch {
            assertionFailure()
        }
    }
    
}


// MARK: - Internal view

private struct HorizontalyCenteredProgressView: View {
    
    var body: some View {
        HStack {
            Spacer(minLength: 0)
            ProgressView()
            Spacer(minLength: 0)
        }
    }
    
}

// MARK: - Internal view

private struct TextsView: View {
    
    let style: displayStyle
    
    enum displayStyle {
        case hide
        case show(title: String?, desc: String?, url: URL?)
    }
    
    private var title: String? {
        switch style {
        case .hide:
            return " "
        case .show(title: let title, _, _):
            return title
        }
    }

    private var desc: String? {
        switch style {
        case .hide:
            return " "
        case .show(title: _, desc: let desc, _):
            return desc
        }
    }
    
    private var link: String? {
        switch style {
        case .hide:
            return " "
        case .show(title: _, desc: _, url: let url):
            return url?.absoluteString
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0.0) {
            
            if let title {
                Text(title)
                    .font(.body.bold())
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
            
            if let desc {
                Text(desc)
                    .font(.body)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
            
            if let link {
                Text(link)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
        }

    }
    
}


// MARK: - Internal view

private struct IconView: View {
    
    let uiImage: UIImage?
    
    private static let size: CGFloat = 50.0
    
    var body: some View {
        Group {
            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: Self.size, height: Self.size)
            } else {
                Image(systemIcon: .safari)
                    .foregroundStyle(.secondary)
                    .imageScale(.medium)
                    .frame(width: Self.size, height: Self.size)
                    .background(Color(UIColor.quaternarySystemFill))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18.0))
    }
    
}


#if DEBUG

private final class DataSourceForPreviews {}

extension DataSourceForPreviews: ComposeLinkPreviewViewDataSource {
    
    func getAsyncStreamOfComposeLinkPreviewViewModel(_ view: ComposeLinkPreviewView, attachmentIdentifier: ComposeAttachmentView.AttachmentIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ComposeLinkPreviewView.Model>) {
        let stream = AsyncStream<ComposeLinkPreviewView.Model> { (continuation: AsyncStream<ComposeLinkPreviewView.Model>.Continuation) in
            Task {
                try? await Task.sleep(seconds: 1)
                let model = ComposeLinkPreviewView.Model(
                    image: nil,
                    title: "Title",
                    desc: "The description",
                    url: URL(string: "https://olvid.io"))
                continuation.yield(model)
            }
        }
        return (UUID(), stream)
    }
    
    func finishAsyncStreamOfComposeLinkPreviewViewModel(_ view: ComposeLinkPreviewView, streamUUID: UUID) {
        // Do nothing for previews
    }
    
    
}

extension DataSourceForPreviews: ComposeLinkPreviewViewActions {
    
    func userWantsToDeleteDraftAttachment(_ view: ComposeLinkPreviewView, attachmentIdentifier: ComposeAttachmentView.AttachmentIdentifier) async throws {
        print("User wants to delete a draft attachment")
    }
    
}

@MainActor
private let dataSourceForPreviews = DataSourceForPreviews()


#Preview {
    VStack {
        Rectangle().fill(.blue)
            .frame(height: 50)
        ComposeLinkPreviewView(linkPreviewIdentifier: .persistedDraftFyleJoinObjectID(NSManagedObjectID()),
                               dataSource: dataSourceForPreviews,
                               actions: dataSourceForPreviews)
        Rectangle().fill(.blue)
            .frame(height: 50)
    }
}

#endif
