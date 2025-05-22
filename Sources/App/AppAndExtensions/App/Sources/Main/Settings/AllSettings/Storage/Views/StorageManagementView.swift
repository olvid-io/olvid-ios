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

@available(iOS 17.0, *)
struct StorageManagementView<Model: StorageManagementViewModelProtocol>: View {
    
    @Environment(\.dismiss) private var dismiss
    
    var model: Model
    
    init(model: Model) {
        self.model = model
    }
    
    @ViewBuilder
    var content: some View {
        
        if let chartModel = model.chartModel, let largestFilesModel = model.largestFilesModel, let sentByMeModel = model.sentByMeModel {
        
            if model.files.isEmpty {
                
                ObvContentUnavailableView(title: String(localized: "STORAGE_MANAGEMENT_CONTENT_UNAVAILABLE_TITLE"),
                                          systemIcon: .externaldriveFill,
                                          description: String(localized: "STORAGE_MANAGEMENT_CONTENT_UNAVAILABLE_DESCRIPTION"))
                
            } else {
                
                List {
                    Section {
                        StorageManagementChartView(model: chartModel)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                model.goToAllFiles()
                            }
                    }
                    
                    if !sentByMeModel.storageFiles.isEmpty || !largestFilesModel.storageFiles.isEmpty {
                        
                        Section(header: Text("STORAGE_DELETE_ELEMENTS_HEADER")) {
                            
                            VStack(alignment: .leading) {
                                
                                if !sentByMeModel.storageFiles.isEmpty {
                                    Text("STORAGE_SENT_BY_ME_HEADER")
                                    StorageManagementInlineFilesView(model: sentByMeModel)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            model.goToFilesSentByMe()
                                        }
                                }
                                
                                if !sentByMeModel.storageFiles.isEmpty && !largestFilesModel.storageFiles.isEmpty {
                                    Divider().padding(.vertical, 8)
                                }
                                
                                if !largestFilesModel.storageFiles.isEmpty {
                                    Text("STORAGE_LARGEST_FILES_HEADER_\(model.largestFilesLocalizedThreshold)")
                                    StorageManagementInlineFilesView(model: largestFilesModel)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            model.goToLargestFiles()
                                        }
                                        .padding(.bottom, 4.0)
                                }
                            }
                        }
                    }
                    
                    if !model.discussionsSorted.isEmpty {
                        Section {
                            ForEach(model.discussionsSorted, id: \.self) { discussion in
                                StorageManagementDiscussionCellView(model: StorageManagementDiscussionCellViewModel(discussion: discussion, files: model.filesPerDiscussions[discussion] ?? []))
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        model.goToDiscussion(discussion)
                                    }
                                    .alignmentGuide(.listRowSeparatorLeading) { dimensions in
                                        dimensions[.leading]
                                    }
                                    .alignmentGuide(.listRowSeparatorTrailing) { dimensions in
                                        dimensions[.trailing]
                                    }
                            }
                        } header: {
                            HStack {
                                Text("STORAGE_DISCUSSION_HEADER").textCase(.uppercase)
                                Spacer()
                                if model.discussionsSorted.count > 1 {
                                    Menu {
                                        ForEach(StorageManagementSortOrder.discussions, id: \.rawValue) { sortOrder in
                                            Button(action: {
                                                withAnimation {
                                                    model.updateDiscussionSortOrder(sortOrder: sortOrder)
                                                }
                                            }) {
                                                HStack {
                                                    sortOrder.title
                                                    if model.discussionSortOrder == sortOrder {
                                                        Spacer()
                                                        model.discussionSortDirection.icon
                                                    }
                                                }
                                            }
                                        }
                                    } label: {
                                        HStack(spacing: 4.0) {
                                            model.discussionSortOrder.title
                                                .font(.callout)
                                            Image(systemIcon: .chevronUpChevronDown)
                                        }
                                        .foregroundStyle(Color(uiColor: .label))
                                    }
                                    .transaction { transaction in
                                        transaction.animation = nil
                                    }
                                }
                            }
                        }
                        .textCase(nil) //https://developer.apple.com/forums/thread/655524
                        
                    }
                }
                
            }
            
            
        } else {
            AnimatedLoader()
                .frame(width: 80.0,
                       height: 80.0)
        }
                
    }
    var body: some View {
//        let _ = Self._printChanges() // Use to print changes to observable

        content
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("STORAGE_MANAGEMENT")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    CloseButton()
                }
            }
        }
        .task {
            await model.onTaskForChartModel()
        }
        .task {
            await model.onTaskForLargestFilesModel()
        }
        .task {
            await model.onTaskForSentByMeModel()
        }
    }
}

private struct CloseButton: View {
    
    var body: some View {
        Image(systemIcon: .xmarkCircleFill)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(Color.secondary)
            .font(.system(size: 22))
    }
}
