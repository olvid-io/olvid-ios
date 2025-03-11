/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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

import UIKit
@preconcurrency import MapKit
import ObvSettings
import CryptoKit

extension ObvLocationService {
    
    private static var snapshotSize: CGSize {
        return CGSize(width: CGFloat(200), height: CGFloat(200))
    }
    
    public static func requestSnapshot(latitude: Double,
                                       longitude: Double,
                                       filename: String) async throws -> UIImage {
        
        // If a cached version exists for a snapshot, we do not want to generate another one.
        if let cachedSnapshot = getCachedSnapshot(filename: filename) {
            return cachedSnapshot
        }
        
        let options = MKMapSnapshotter.Options()
        
        let location = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        
        let zoomValue = 0.002
        
        let span = MKCoordinateSpan(latitudeDelta: zoomValue, longitudeDelta: zoomValue)
        
        options.region = MKCoordinateRegion(center: location,
                                            span: span)
        
        options.size = ObvLocationService.snapshotSize
        
        options.mapType = .standard
        
        let snapshotter = MKMapSnapshotter(options: options)
        
        let snapshot = try await snapshotter.start()
        
        saveCachedSnapshot(with: snapshot.image,
                           latitude: latitude,
                           longitude: longitude,
                           filename: filename)
        
        return snapshot.image
    }
    
    private static func getCachedSnapshot(filename:String) -> UIImage? {
        
        let snapshotURL = ObvUICoreDataConstants.ContainerURL.forMapSnapshots.appendingPathComponent(filename)
        
        if FileManager.default.fileExists(atPath: snapshotURL.path),
           let imageData = try? Data(contentsOf: snapshotURL) {
            return UIImage(data: imageData)
        } else {
            return nil
        }
    }
    
    private static func saveCachedSnapshot(with image: UIImage,
                                           latitude: Double,
                                           longitude:Double,
                                           filename:String) {
        
        guard let imageData = image.pngData() else { return }
        
        let snapshotURL = ObvUICoreDataConstants.ContainerURL.forMapSnapshots.appendingPathComponent(filename)
        
        if !FileManager.default.fileExists(atPath: snapshotURL.path) {
            try? imageData.write(to: snapshotURL)
        }
    }
    
    public static func removeCachedMapSnapshotGenerated(olderThan dateLimit: Date) {
        let snapshotDir = ObvUICoreDataConstants.ContainerURL.forMapSnapshots.url
        
        guard FileManager.default.fileExists(atPath: snapshotDir.path) else { return }
        let includingPropertiesForKeys: [URLResourceKey] = [
            .creationDateKey,
            .isWritableKey,
            .isRegularFileKey,
        ]
        guard let fileURLs = try? FileManager.default.contentsOfDirectory(at: snapshotDir, includingPropertiesForKeys: includingPropertiesForKeys, options: .skipsHiddenFiles) else { return }
        for fileURL in fileURLs {
            guard let attributes = try? fileURL.resourceValues(forKeys: Set(includingPropertiesForKeys)) else { continue }
            guard attributes.isWritable == true else { continue }
            guard attributes.isRegularFile == true else { continue }
            guard let creationDate = attributes.creationDate, creationDate < dateLimit else { continue }
            // If we reach this point, we should delete the archive
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
    
}
