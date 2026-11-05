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
import ObvDesignSystem
import ObvAppTypes

/// A view that displays link metadata including title, description, URL, and optional image.
struct LinkMetadataView: View {
    
    let url: URL
    let metadata: ObvLinkMetadata
    
    // Determine if the image should be treated as an icon based on size
    private var imageDisplayMode: ImageDisplayMode {
        guard let image = metadata.image else { return .none }
        let size = image.size
        if size.width < 400 && size.height < 400 {
            return .icon(image)
        } else {
            return .banner(image)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Image preview if it's a large banner image
            if case .banner(let image) = imageDisplayMode {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxHeight: 200)
                    .clipped()
            }
            
            // Content section with title and source info
            VStack(alignment: .leading, spacing: 8) {
                // Description
                if let desc = metadata.desc, !desc.isEmpty {
                    Text(desc)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                
                // Source info with icon and URL
                HStack(spacing: 10) {
                    // Favicon or placeholder icon
                    if case .icon(let iconImage) = imageDisplayMode {
                        Image(uiImage: iconImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 32, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    
                    // Title and host
                    VStack(alignment: .leading, spacing: 2) {
                        if let title = metadata.title {
                            Text(title)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                        
                        if let host = (metadata.url ?? url).host {
                            Text(host)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
    
                    }
                    
                    Spacer()
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
    }
    
    // MARK: - Helper Types
    
    private enum ImageDisplayMode {
        case none
        case icon(UIImage)
        case banner(UIImage)
    }
}

// MARK: - Previews

#if DEBUG

#Preview("Link with Banner Image") {
    // Create a large image (banner)
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 600))
    let bannerImage = renderer.image { ctx in
        UIColor.systemBlue.setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
    }
    
    let metadata = ObvLinkMetadata(
        title: "121K vues, 7,450 J'aime : 🍓 TARTE AUX FRAISES",
        desc: "Découvrez cette délicieuse recette",
        url: URL(string: "https://www.instagram.com/celineduhamel")!,
        pngData: bannerImage.pngData()
    )
    
    VStack {
        LinkMetadataView(
            url: URL(string: "https://www.instagram.com")!,
            metadata: metadata
        )
        .padding()
        
        Spacer()
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Link with Icon Image") {
    // Create a small image (icon)
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100))
    let iconImage = renderer.image { ctx in
        UIColor.systemRed.setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        
        // Draw a simple shape
        UIColor.white.setFill()
        ctx.cgContext.fillEllipse(in: CGRect(x: 25, y: 25, width: 50, height: 50))
    }
    
    let metadata = ObvLinkMetadata(
        title: "Link with Small Icon",
        desc: "This link has a small image that will be displayed as an icon next to the URL.",
        url: URL(string: "https://www.example.com/with-icon")!,
        pngData: iconImage.pngData()
    )
    
    VStack {
        LinkMetadataView(
            url: URL(string: "https://www.example.com")!,
            metadata: metadata
        )
        .padding()
        
        Spacer()
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Link without Image") {
    let metadata = ObvLinkMetadata(
        title: "Link Without Any Image",
        desc: "This link preview doesn't have an associated image, only text content with a default globe icon.",
        url: URL(string: "https://www.example.com/no-image")!,
        pngData: nil
    )
    
    VStack {
        LinkMetadataView(
            url: URL(string: "https://www.example.com")!,
            metadata: metadata
        )
        .padding()
        
        Spacer()
    }
    .background(Color(.systemGroupedBackground))
}

#endif
