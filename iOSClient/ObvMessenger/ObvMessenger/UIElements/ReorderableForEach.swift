/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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

@available(iOS 15, *)
protocol ReorderableItem: Identifiable & Equatable {
}

@available(iOS 15, *)
struct ItemView<Content: View, Item: ReorderableItem>: View {

    let item: Item
    let content: (Item) -> Content
    let none: Item

    @Binding var items: [Item]
    @Binding var currentDrop: Item?

    var body: some View {
        HStack {
            if item != none, item == currentDrop {
                /// Show empty space at left, use content to have the same size
                content(item)
                    .opacity(0.0)
            }
            content(item)
        }
        .background {
            /// Be able to be tapped everywhere
            Rectangle()
                .opacity(0.00001)
        }
    }

}

@available(iOS 15, *)
struct ReorderableForEach<Content: View, Item: ReorderableItem>: View {
    @Binding private var items: [Item]
    @Binding private var draggedItem: Item?
    private let none: Item
    private let content: (Item) -> Content
    private let haptic: () -> Void

    init(items: Binding<[Item]>,
         draggedItem: Binding<Item?>,
         haptic: @escaping () -> Void,
         none: Item,
         @ViewBuilder content: @escaping (Item) -> Content) {
        self._items = items
        self._draggedItem = draggedItem
        self.haptic = haptic
        self.none = none
        self.content = content
    }

    @State private var currentDrop: Item?

    /// List of items with an aditional none element
    private var itemsWithLastSpace: [Item] {
        var result = items
        result += [none]
        return result
    }

    var body: some View {
        ForEach(itemsWithLastSpace) { item in
            ItemView(item: item,
                     content: content,
                     none: none,
                     items: $items,
                     currentDrop: $currentDrop
            )
                .if(item != none) { view in
                    /// Drag remove the item from the list
                    view.onDrag({
                        if draggedItem == nil {
                            haptic()
                        }
                        withAnimation {
                            draggedItem = item
                            items.removeAll(where: { $0 == item })
                        }
                        return NSItemProvider(object: "\(item.id)" as NSString)
                    }, preview: {
                        content(item)
                            .frame(width: 60.0, height: 60.0, alignment: .center)
                            .scaleEffect(1.5)
                    })
                }
                .background(
                    /// Shows a circle to represent the none element at the end of the list.
                    DottedCircle(radius: 18.0)
                        .opacity(item == none ? 1.0 : 0.0), alignment: .center)
                .onDrop(
                    of: [UTType.text],
                    delegate: DropRelocateDelegate(
                        item: item,
                        none: none,
                        haptic: haptic,
                        items: $items,
                        draggedItem: $draggedItem,
                        currentDrop: $currentDrop
                    ))
        }
    }
}

@available(iOS 15, *)
struct DropRelocateDelegate<Item: ReorderableItem>: DropDelegate {
    let item: Item
    let none: Item
    let haptic: () -> Void
    @Binding var items: [Item]
    @Binding var draggedItem: Item?
    @Binding var currentDrop: Item?

    private func debug(_ name: String) {
        #if false
            print("\(name) item:\(item) items:\(items)")
        #endif
    }

    func dropEntered(info: DropInfo) {
        debug("dropEntered")
        guard item != draggedItem else { return }
        haptic()
        withAnimation {
            currentDrop = item
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        debug("performDrop")
        if let draggedItem = draggedItem {
            withAnimation {
                if item == none {
                    items.append(draggedItem)
                } else if let to = items.firstIndex(of: item) {
                    items.insert(draggedItem, at: to)
                    self.currentDrop = nil
                }
                self.draggedItem = nil
            }
            return true
        } else {
            return false
        }
    }

    func dropExited(info: DropInfo) {
        debug("dropExited")
        withAnimation {
            currentDrop = nil
        }
    }

    func validateDrop(info: DropInfo) -> Bool {
        /// Avoid to drop an item twice.
        guard let draggedItem = draggedItem else { return false }
        return !items.contains(draggedItem)
    }

}
