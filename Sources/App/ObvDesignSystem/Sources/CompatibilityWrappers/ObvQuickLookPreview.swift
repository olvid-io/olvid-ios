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
import QuickLook


extension View {

    /// Presents a Quick Look preview of the file at `item`, like `quickLookPreview(_:)`. Call this instead of SwiftUI's
    /// modifier in every module built for Mac Catalyst.
    ///
    /// On Mac Catalyst, SwiftUI's modifier lives in `_QuickLook_SwiftUI`, which macOS 13 does not have. A binary that calls
    /// it does not launch there, and `#available` cannot prevent it because the SDK marks it available. So on Catalyst the
    /// call is compiled out and a `QLPreviewController` is presented in a sheet.
    public func quickLookPreviewBackedByUIKitOnCatalyst(_ item: Binding<URL?>) -> some View {
        #if targetEnvironment(macCatalyst)
        return self.modifier(QuickLookPreviewInSheet(item: item, items: []))
        #else
        return self.quickLookPreview(item)
        #endif
    }


    /// Presents a Quick Look preview of `selection`, an element of `items`, like `quickLookPreview(_:in:)`. See
    /// ``quickLookPreviewBackedByUIKitOnCatalyst(_:)``.
    public func quickLookPreviewBackedByUIKitOnCatalyst(_ selection: Binding<URL?>, in items: [URL]) -> some View {
        #if targetEnvironment(macCatalyst)
        return self.modifier(QuickLookPreviewInSheet(item: selection, items: items))
        #else
        return self.quickLookPreview(selection, in: items)
        #endif
    }

}


private struct QuickLookPreviewInSheet: ViewModifier {

    @Binding var item: URL?
    let items: [URL]

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: Binding(get: { item != nil }, set: { if !$0 { item = nil } })) {
                if let item {
                    PreviewController(url: item, urls: items.isEmpty ? [item] : items)
                }
            }
    }

}


private struct PreviewController: UIViewControllerRepresentable {

    let url: URL
    let urls: [URL]

    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        controller.currentPreviewItemIndex = urls.firstIndex(of: url) ?? 0
        return UINavigationController(rootViewController: controller)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(urls: urls)
    }

    final class Coordinator: QLPreviewControllerDataSource {

        private let urls: [URL]

        init(urls: [URL]) {
            self.urls = urls
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            urls.count
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            urls[index] as NSURL
        }

    }

}
