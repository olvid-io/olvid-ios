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
struct StorageManagementFileListView<Model: StorageManagementFileListViewModelProtocol>: View {
    
    @State private var panGesture: UIPanGestureRecognizer?
    @State private var bottomViewHeight: CGFloat = 0
    
    private let minCellWidth: CGFloat = 120.0
    private let maxCellWidth: CGFloat = 150.0
    
    @State private var topInset: CGFloat = 0.0

    @Environment(\.dismiss) private var dismiss

    var model: Model

    /// Esc leaves select mode first, and otherwise goes back to the screen this list was pushed from.
    private func answersTheEscapeKey() {
        if model.isSelectionEnabled {
            withAnimation {
                model.toggleSelectionMode()
            }
        } else {
            dismiss()
        }
    }
    
    init(model: Model) {
        self.model = model
    }

    /// How many files are chosen. The trash was here until 2026-09-07 and is now in the navigation bar, which is where the discussions list, the single
    /// discussion screen and the gallery all keep the actions of their own select modes.
    ///
    /// **The bar stays for the count**, which has nowhere else to go, and its height still feeds `bottomViewHeight` so that the grid can scroll clear of it.
    var selectionBottomView: some View {
        Text("STORAGE_ITEMS_SELECTED_\(numberOfSelectedFiles)")
            .font(.headline)
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

    /// What the count says, and what decides whether the trash is offered. Chosen minus those already on their way out, as the bar has always counted them.
    private var numberOfSelectedFiles: Int {
        model.selectionProperties.multipleSelections.count - model.selectionProperties.toBeDeleted.count
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
        .quickLookPreviewBackedByUIKitOnCatalyst(Binding(get: { self.model.quicklookURL }, set: { self.model.setQuicklookURL($0) }), in: model.quicklookURLs)
        .padding(.horizontal, -2.0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Hidden, because what Esc does depends on whether files are being chosen; ``answersTheEscapeKey()`` decides.
        .escapeKeyPresses(answersTheEscapeKey)
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
        // Each control gets a capsule of its own on iOS 26, which takes both the separate items *and* the spacers: everything at one placement shares a
        // background unless a `ToolbarSpacer` breaks it. Nothing is needed before 26, where the bar draws no capsules at all.
        .toolbar {
            if model.isSelectionEnabled {
                ToolbarItem(placement: .topBarTrailing) {
                    theDeletionOfWhatIsChosen
                }
                if #available(iOS 26.0, *) {
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    theWayOutOfChoosing
                }
            } else {
                if model.storageFiles.count > 1 {
                    ToolbarItem(placement: .topBarTrailing) {
                        theSortOrder
                    }
                    if #available(iOS 26.0, *) {
                        ToolbarSpacer(.fixed, placement: .topBarTrailing)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    theWayIntoChoosing
                }
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
    
    /// The order the files are listed in. Offered only when there is more than one of them, and never while the reader is choosing.
    var theSortOrder: some View {
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

    /// The way into choosing files.
    ///
    /// **One transaction, as on the two other screens that have this mode**, and for the same reason: entering carries the navigation items swapping, the bar
    /// at the bottom arriving and the grid's own bottom padding changing with it. They are one movement to the eye, and without an animation they are three
    /// cuts. See ``theWayOutOfChoosing``, which says it from the other side.
    var theWayIntoChoosing: some View {
        Button(action: {
            withAnimation {
                model.toggleSelectionMode()
            }
        }) {
            Text("SELECT")
        }
    }

    /// The way out of choosing: an xmark, as in Photos' own select mode and as on the three other screens of this app that offer one. The word this button
    /// used to show survives as the accessibility label, so VoiceOver reads a verb rather than a glyph name.
    var theWayOutOfChoosing: some View {
        Button(action: {
            withAnimation {
                model.toggleSelectionMode()
            }
        }) {
            Image(systemIcon: .xmark)
        }
        .accessibilityLabel(Text("Cancel"))
    }

    /// Deleting what is chosen — moved up from the bar at the bottom on 2026-09-07, where the other select modes of this app keep their own actions.
    ///
    /// **Red, and a bare trash rather than a menu**, which is how that argument settled on the single discussion screen: destructive styling belongs to the
    /// *entry* of a menu, where a reader reads a word rather than aims at a glyph — but only where there is a menu, and a menu of a single entry is a worse
    /// control than the entry itself. Deleting is the only thing on offer here, so the styling has nowhere else to go.
    ///
    /// **Disabled rather than hidden** while nothing is chosen, as on the other screens: a bar that rearranges itself as the reader works is worse than one
    /// that greys.
    var theDeletionOfWhatIsChosen: some View {
        Button(role: .destructive, action: {
            model.showDeletionAlert(value: true)
        }) {
            Image(systemIcon: .trash)
        }
        .tint(Color(uiColor: .systemRed))
        .disabled(numberOfSelectedFiles == 0)
    }
}
