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

@available(iOS 17.0, *)
struct StorageManagementFileListView<Model: StorageManagementFileListViewModelProtocol>: View {
    
    @State private var panGesture: UIPanGestureRecognizer?
    @State private var bottomViewHeight: CGFloat = 0
    
    private let minCellWidth: CGFloat = 120.0
    private let maxCellWidth: CGFloat = 150.0
    
    @State private var topInset: CGFloat = 0.0
    
    var model: Model
    
    init(model: Model) {
        self.model = model
    }

    var selectionBottomView: some View {
        HStack(alignment: .center) {
            Spacer()
            Text("STORAGE_ITEMS_SELECTED_\(model.selectionProperties.multipleSelections.count - model.selectionProperties.toBeDeleted.count)")
                .font(.headline)
            Spacer()
                .overlay() {
                    HStack {
                        Spacer()
                        Button(action: {
                            model.showDeletionAlert(value: true)
                        }) {
                            Image(systemIcon: .trash)
                                .foregroundStyle(Color(uiColor: .label))
                                .padding(20.0)
                        }
                    }
                }
        }
        .padding(.vertical, 20.0)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial)
        .overlay {
            GeometryReader { geometry -> Color in
                DispatchQueue.main.async {
                    self.bottomViewHeight = geometry.size.height + 2.0
                }
                return Color.clear
            }
        }
    }
    
    var body: some View {
        
//        let _ = Self._printChanges() // Use to print changes to observable
        
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: minCellWidth, maximum: maxCellWidth), spacing: 0.0)], spacing: 0.0) {
                ForEach(model.storageFiles, id: \.self) { file in
                    model.cellForStorageFile(file, isSelected: model.isFileSelected(fyleMessageJoin: file))
                        .contentShape(Rectangle()) // Use to fix problem with Tap Gesture
                        .contextMenu {
                            Button(action: {
                                model.goToDiscussion(for: file)
                            }) {
                                Text("SHOW_IN_DISCUSSION")
                                Image(systemIcon: .bubbleLeftAndBubbleRight)
                            }
                            if file.deleteActionCanBeMadeAvailable {
                                Button(role: .destructive, action: {
                                    model.delete(file)
                                }) {
                                    Text("Delete")
                                    Image(systemIcon: .trash)
                                }
                            }
                        }
                        .padding(.all, 1.0)
                        .id(file)
                        .aspectRatio(1, contentMode: .fill)
                        .onGeometryChange(for: CGRect.self) {
                            let frame = $0.frame(in: .scrollView)
                            return CGRect(origin: CGPoint(x: frame.origin.x, y: frame.origin.y + topInset),
                                          size: frame.size)
                        } action: { newValue in
                            model.updateStorageFileLocation(for: file, frame: newValue)
                        }
                        .onTapGesture {
                            if model.isSelectionEnabled {
                                model.toggleSelection(for: file)
                            } else {
                                model.itemHasBeenTapped(for: file)
                            }
                        }
                }
            }
            .scrollTargetLayout()
            .safeAreaPadding(.bottom, bottomViewHeight)
        }
        .modifier(QuicklookPreviewModifier(model: self.model))
        .padding(.horizontal, -2.0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: model.isSelectionEnabled) { _, newValue in
            panGesture?.isEnabled = newValue
            if !newValue {
                self.bottomViewHeight = 0
            }
        }
        .panGesture(panGesture: $panGesture,
                    panIsEnabled: model.isSelectionEnabled,
                    onGestureChange: onGestureChange(_:),
                    onGestureEnded: onGestureEnded(_:))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                toolbar
            }
        }
        .overlay(alignment: .bottom) {
            if model.isSelectionEnabled {
                selectionBottomView
            }
        }
        .overlay {
            GeometryReader { geometry -> Color in
                DispatchQueue.main.async {
                    self.topInset = geometry.safeAreaInsets.top
                }
                return Color.clear
            }
        }
        .task {
            do {
                try await model.onTask()
            } catch { }
        }
        .modifier(ConfirmDialogModifier(model: model))
    }
    
    private func onGestureChange(_ gesture: UIPanGestureRecognizer) {
        let position = gesture.location(in: gesture.view)
        if let fallingIndex = model.storageFilesLocation.firstIndex(where:{ $0.contains(position) }),
           let fyleMessageJoin = model.storageFiles[safe: fallingIndex] {
            model.updateSelection(for: fyleMessageJoin)
        }
    }
    
    private func onGestureEnded(_ gesture: UIPanGestureRecognizer) {
        model.clearSelection()
    }
}

@available(iOS 17.0, *)
extension StorageManagementFileListView {
    
    var toolbar: some View {
        HStack(alignment: .center, spacing: 2.0) {

            if model.storageFiles.count > 1 && !model.isSelectionEnabled {
                Menu {
                    ForEach(StorageManagementSortOrder.files, id: \.rawValue) { sortOrder in
                        Button(action: {
                            withAnimation {
                                model.updateSortOrder(sortOrder: sortOrder)
                            }
                        }) {
                            HStack {
                                sortOrder.title
                                if model.sortOrder == sortOrder {
                                    Spacer()
                                    model.sortDirection.icon
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemIcon: .arrowUpArrowDown)
                }
            }

            Button(action: {
                model.toggleSelectionMode()
            }) {
                if model.isSelectionEnabled {
                    Text("Cancel")
                } else {
                    Image(systemIcon: .trash)
                }
            }
        }
    }
}
