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
struct StorageManagementInlineFilesView<Model: StorageManagementInlineFilesViewModelProtocol>: View {
    
    var model: Model
    
    @State private var totalHeight = 100.0 // No matter what value is there
    
    init(model: Model) {
        self.model = model
    }
    
    @ViewBuilder
    private func cellForRemainingStorageFiles(_ remainingStorageFiles: [Model.StorageFileRepresentation]) -> some View {
        ZStack {
            if let firstRemainingFile = remainingStorageFiles.first {
                model.cellForStorageFile(firstRemainingFile)
            } else {
                Rectangle()
                    .background(Color(uiColor: .tertiarySystemGroupedBackground))
            }
            
            Text(verbatim: "+ \(remainingStorageFiles.count)")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.5))
        }
        .padding(1.0)
    }
    
    var body: some View {
//        let _ = Self._printChanges() // Use to print changes to observable
        
        return GeometryReader() { proxy in
            
            if proxy.size.width > 0 {
                
                let numberOfFiles = getAccurateNumberOfFilesDisplayed(with: proxy.size.width)
                
                let cellWidth = (proxy.size.width / CGFloat(numberOfFiles)) - 0.1
                
                WrappingHStack(data: model.storageFiles,
                               cellAlignment: .top,
                               cellSpacing: 0.0,
                               width: proxy.size.width,
                               maxRows: 1,
                               cornerRadius: 12.0,
                               contentForTruncatedElements: { remainingStorageFiles in
                    cellForRemainingStorageFiles(remainingStorageFiles)
                        .frame(width: cellWidth,
                               height:cellWidth)
                }, content: { storageFile in
                    return model.cellForStorageFile(storageFile)
                        .padding(1.0)
                        .frame(width: cellWidth,
                               height:cellWidth)
                })
                .background(GeometryReader { bgProxy -> Color in // Trick to fix issue with geometryReader messing with height
                    DispatchQueue.main.async {
                        self.totalHeight = bgProxy.size.height
                    }
                    return Color.clear
                })
            }
        }
        .frame(height: totalHeight)
        .task {
            do {
                try await model.onTask()
            } catch {
                
            }
        }
    }
}

@available(iOS 17.0, *)
extension StorageManagementInlineFilesView {
    
    func getAccurateNumberOfFilesDisplayed(with referenceWidth: CGFloat) -> Int {
        var bestNumberOfFiles = 0
        
        // On parcourt les cellWidth possibles de 75 à 125 pixels (plage comprise)
        for cellWidth in stride(from: 75.0, to: 125.0, by: 0.1) {
            let numberOfFiles = referenceWidth / cellWidth
            
            // Si cellWidth * numberOfFiles est égal à referenceWidth (avec une petite tolérance pour éviter les problèmes d'arrondi)
            if abs(numberOfFiles.rounded(.down) * cellWidth - referenceWidth) < 0.01 {
                bestNumberOfFiles = Int(numberOfFiles.rounded(.down))
                break // On privilégie le plus grand nombre de fichiers possible
            }
        }
        
        // Si aucune solution n'a été trouvée
        if bestNumberOfFiles == 0 {
            return 4
        }
        
        return bestNumberOfFiles
    }
}
