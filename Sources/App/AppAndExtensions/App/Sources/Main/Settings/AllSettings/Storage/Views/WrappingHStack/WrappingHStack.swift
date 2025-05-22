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

/// A view used to display HStack but limited to width available.
///

struct WrappingHStack<Content: View, TruncatedContent: View, T: Identifiable & Hashable>: View {
    
    typealias Row = [T]
    typealias Rows = [Row]
    
    struct Layout: Equatable {
        let cellAlignment: VerticalAlignment
        let cellSpacing: CGFloat
        let width: CGFloat
        let cornerRadius: CGFloat
        let maxRows: Int?
    }
    
    private var data: [T]
    private let contentForTruncatedElements: (([T]) -> TruncatedContent)?
    private let content: (T) -> Content
    private let layout: Layout
    
    @State private var truncatedElements: [T]?
    @State private var rows: Rows = Rows()
    @State private var sizes: [CGSize] = [CGSize]()
    
    /// Initialises a WrappingHStack instance.
    /// - Parameters:
    ///   - data: An array of elements of type `T` whose elements are used to initialise a "cell" view.
    ///   - cellAlignment: An alignment position along the horizontal axis. If not specified the default is `firstTextBaseline`.
    ///   - cellSpacing: The spacing between the cell views, or `nil` if you want the view to choose a default distance.
    ///   - rowSpacing: The spacing between the rows, or `nil` if you want the view to choose a default distance.
    ///   - width: The available width for laying out the cells.
    ///   - content: Returns a cell view.
    init(data: [T],
         cellAlignment: VerticalAlignment = .firstTextBaseline,
         cellSpacing: CGFloat = 8.0,
         width: CGFloat,
         maxRows: Int? = nil,
         cornerRadius: CGFloat = 0.0,
         contentForTruncatedElements: (([T]) -> TruncatedContent)? = nil,
         content: @escaping (T) -> Content) {
        self.data = data
        self.content = content
        self.contentForTruncatedElements = contentForTruncatedElements
        self.layout = .init(
            cellAlignment: cellAlignment,
            cellSpacing: cellSpacing,
            width: width,
            cornerRadius: cornerRadius,
            maxRows: maxRows)
    }
    
    var body: some View {
        
//        let _ = Self._printChanges() // Use to print changes to observable
        
        buildView(
            rows: rows,
            content: content,
            contentForTruncatedElements: contentForTruncatedElements,
            layout: layout
        )
    }
    
    @ViewBuilder
    private func buildView(rows: Rows,
                           content: @escaping (T) -> Content,
                           contentForTruncatedElements: (([T]) -> TruncatedContent)?,
                           layout: Layout) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(rows, id: \.self) { row in
                HStack(alignment: layout.cellAlignment, spacing: layout.cellSpacing) {
                    ForEach(row, id: \.self) { value in
                        if let truncatedElements, let contentForTruncatedElements, row == rows.last, value == row.last {
                            contentForTruncatedElements(truncatedElements)
                        } else {
                            content(value)
                        }
                    }
                }
                .cornerRadius(layout.cornerRadius)
            }
        }
        .background(
            calculateCellSizesAndRows(data: data, content: content) { sizes in
                self.sizes = sizes
            }
                .onChange(of: layout) { layout in
                    self.rows = calculateRows(layout: layout)
                }
        )
    }
    
    // Populates a HStack with the calculated cell content. The size of each cell
    // will be stored through a view preference accessible with key
    // `SizeStorePreferenceKey`. Once the cells are layout, the completion
    // callback `result` will be called with an array of CGSize
    // representing the cell sizes as its argument. This should be used to store
    // the size array in some state variable. The function continues to calculate
    // the rows based on the cell sizes and the layout.
    // Returns the hidden HStack. This HStack will never be rendered on screen.
    // Will be called only when data or content changes. This is likely the
    // most expensive part, since it requires calculating the size of each
    // cell.
    private func calculateCellSizesAndRows(
        data: [T],
        content: @escaping (T) -> Content,
        result: @escaping ([CGSize]) -> Void
    ) -> some View {
        // Note: the HStack is required to layout the cells as _siblings_ which
        // is required for the SizeStorePreferenceKey's reduce function to be
        // invoked.
        HStack {
            ForEach(data, id: \.self) { element in
                content(element)
                    .calculateSize()
            }
        }
        .onPreferenceChange(SizeStorePreferenceKey.self) { sizes in
            result(sizes)
            self.rows = calculateRows(layout: layout)
        }
        .hidden()
    }
    
    // Will be called when the layout changes. This happens whenever the
    // orientation of the device changes or when the content views changes
    // its size. This function is quite inexpensive, since the cell sizes will
    // not be calclulated.
    private func calculateRows(layout: Layout) -> Rows {
        guard layout.width > 10 else {
            return []
        }
        self.truncatedElements = nil
        
        let dataAndSize = zip(data, sizes)
        var rows = [[T]]()
        var availableSpace = layout.width
        var elements = ArraySlice(dataAndSize)
        while let (data, size) = elements.first {
            var row = [data]
            availableSpace -= size.width + layout.cellSpacing
            elements = elements.dropFirst()
            while let (nextData, nextSize) = elements.first, (nextSize.width + layout.cellSpacing) <= availableSpace {
                row.append(nextData)
                availableSpace -= nextSize.width + layout.cellSpacing
                elements = elements.dropFirst()
            }
            rows.append(row)
            if
                let maxRows = layout.maxRows,
                maxRows > 0,
                rows.count >= maxRows,
                !elements.isEmpty
            {
                rows = rows.dropLast()
                rows.append(row)
                let elementsDisplayedCount = rows.reduce(0, { $0 + $1.count })
                self.truncatedElements = Array(self.data.dropFirst(elementsDisplayedCount))
                break
            }
            availableSpace = layout.width
        }
        return rows
    }
}

extension WrappingHStack {
    
    struct CellSizes: View, Equatable {
        let data: [T]
        let content: (T) -> Content
        @Binding var cellSizes: [CGSize]
        
        // Populates a HStack with the calculated cell content. The size of each cell
        // will be stored through a view preference accessible with key
        // `SizeStorePreferenceKey`. Once the cells are layout, the completion
        // callback `result` will be called with an array of CGSize
        // representing the cell sizes as its argument. This should be used to store
        // the size array in some state variable.
        // Returns the hidden HStack. This HStack will never be rendered on screen.
        // Will be called only when data or content changes. This is likely the
        // most expensive part, since it requires calculating the size of each
        // cell.
        var body: some View {
            // Note: the HStack is required to layout the cells as _siblings_ which
            // is required for the SizeStorePreferenceKey's reduce function to be
            // invoked.
            HStack() {
                ForEach(data, id: \.id) { element in
                    content(element)
                        .calculateSize()
                }
            }
            .onPreferenceChange(SizeStorePreferenceKey.self) { sizes in
                cellSizes = sizes
            }
            .frame(width: 0, height: 0)
            .hidden()
        }
        
        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.data == rhs.data
        }
        
    }
}

fileprivate struct SizeStorePreferenceKey: PreferenceKey {
    static var defaultValue: [CGSize] = []
    
    static func reduce(value: inout [CGSize], nextValue: () -> [CGSize]) {
        value += nextValue()
    }
}

fileprivate struct SizeStoreModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .preference(key: SizeStorePreferenceKey.self,
                                    value: [geometry.size]
                        )
                }
            )
    }
}

fileprivate struct RowStorePreferenceKey<T>: PreferenceKey {
    typealias Row = [T]
    typealias Value = [Row]
    static var defaultValue: Value { [Row]() }
    
    static func reduce(value: inout Value, nextValue: () -> Value) {
        value = nextValue()
    }
}

fileprivate extension View {
    func calculateSize() -> some View {
        modifier(SizeStoreModifier())
    }
}
