/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import ObvUICoreData


final class InternalStorageExplorerViewController: UIViewController, UICollectionViewDelegate {
    
    private enum Section: Int, CaseIterable {
        case directories
        case files
    }

    private enum Item: Hashable {
        case directory(name: String, creationDate: Date, url: URL)
        case file(name: String, creationDate: Date, byteSize: Int, url: URL)
        
        var text: String {
            switch self {
            case .directory(name: let name, creationDate: _, url: _):
                return name
            case .file(name: let name, creationDate: _, byteSize: _, url: _):
                return name
            }
        }
        
        func secondaryText(dateFormater df: DateFormatter, byteCountFormatter bf: ByteCountFormatter) -> String {
            switch self {
            case .directory(name: _, creationDate: let creationDate, url: _):
                return df.string(from: creationDate)
            case .file(name: _, creationDate: let creationDate, byteSize: let byteSize, url: _):
                return [df.string(from: creationDate), bf.string(fromByteCount: Int64(byteSize))].joined(separator: " - ")
            }
        }

        var url: URL {
            switch self {
            case .directory(name: _, creationDate: _, url: let url):
                return url
            case .file(name: _, creationDate: _, byteSize: _, url: let url):
                return url
            }
        }
        
    }
    
    private typealias DataSource = UICollectionViewDiffableDataSource<Section, Item>
    private typealias Snapshot = NSDiffableDataSourceSnapshot<Section, Item>

    private let root: URL
    private weak var collectionView: UICollectionView!
    private var dataSource: DataSource!

    private static let dateFormater: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short
        return df
    }()
    
    private static let byteCountFormatter: ByteCountFormatter = {
        let bf = ByteCountFormatter()
        bf.countStyle = .file
        return bf
    }()
    
    init(root: URL) {
        self.root = root
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = root.lastPathComponent
        configureHierarchy()
        configureDataSource()
        setInitialData()
        
        let action = UIAction(handler: { [weak self] _ in self?.dismiss(animated: true) })
        let doneBarButtomItem = UIBarButtonItem(systemItem: .done, primaryAction: action, menu: nil)
        navigationItem.rightBarButtonItem = doneBarButtomItem
        
    }
    
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard let indexPathsForSelectedItems = collectionView?.indexPathsForSelectedItems else { return }
        for indexPath in indexPathsForSelectedItems {
            collectionView.deselectItem(at: indexPath, animated: true)
        }
    }
    
    // MARK: - Configuring the collection view
    
    private func configureHierarchy() {
        let collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: createLayout())
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .systemBackground
        collectionView.delegate = self

        view.addSubview(collectionView)
        
        self.collectionView = collectionView
                
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    
    private func createLayout() -> UICollectionViewLayout {
        let sectionProvider = { (sectionIndex: Int, layoutEnvironment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection? in
            let configuration = UICollectionLayoutListConfiguration(appearance: .plain)
            let section = NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: layoutEnvironment)
            return section
        }
        return UICollectionViewCompositionalLayout(sectionProvider: sectionProvider)
    }

    
    private func configureDataSource() {
        
        let cellRegistrationForDirectories = UICollectionView.CellRegistration<UICollectionViewListCell, Item> { cell, _, item in
            var content = cell.defaultContentConfiguration()
            content.text = item.text
            content.secondaryText = item.secondaryText(dateFormater: Self.dateFormater, byteCountFormatter: Self.byteCountFormatter)
            content.image = UIImage(systemIcon: .folder)
            content.textProperties.font = UIFont.preferredFont(forTextStyle: .footnote)
            content.secondaryTextProperties.color = .secondaryLabel
            cell.contentConfiguration = content
            cell.accessories = [.disclosureIndicator()]
        }

        let cellRegistrationForFiles = UICollectionView.CellRegistration<UICollectionViewListCell, Item> { cell, _, item in
            var content = cell.defaultContentConfiguration()
            content.text = item.text
            content.secondaryText = item.secondaryText(dateFormater: Self.dateFormater, byteCountFormatter: Self.byteCountFormatter)
            content.image = UIImage(systemIcon: .doc)
            content.textProperties.font = UIFont.preferredFont(forTextStyle: .footnote)
            content.secondaryTextProperties.color = .secondaryLabel
            cell.contentConfiguration = content
        }

        dataSource = DataSource(collectionView: collectionView) { (collectionView: UICollectionView, indexPath: IndexPath, item: Item) -> UICollectionViewCell? in
            switch item {
            case .directory:
                return collectionView.dequeueConfiguredReusableCell(using: cellRegistrationForDirectories, for: indexPath, item: item)
            case .file:
                return collectionView.dequeueConfiguredReusableCell(using: cellRegistrationForFiles, for: indexPath, item: item)
            }
        }
        
    }

    
    private func setInitialData() {
        do {
            let keys: [URLResourceKey] = [
                .isDirectoryKey,
                .nameKey,
                .creationDateKey,
                .fileSizeKey,
            ]            
            let urls = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: keys)
            
            var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()

            // Populate the directories section

            do {
                snapshot.appendSections([.directories])
                let items: [Item] = urls
                    .compactMap { url in
                        guard let values = try? url.resourceValues(forKeys: Set(keys)) else { assertionFailure(); return nil }
                        guard let isDirectory = values.isDirectory else { assertionFailure(); return nil }
                        guard isDirectory else { return nil }
                        guard let name = values.name, let creationDate = values.creationDate else { assertionFailure(); return nil }
                        return Item.directory(name: name, creationDate: creationDate, url: url)
                    }
                snapshot.appendItems(items)
            }
            
            // Populate the files section

            do {
                snapshot.appendSections([.files])
                let items: [Item] = urls
                    .compactMap { url in
                        guard let values = try? url.resourceValues(forKeys: Set(keys)) else { assertionFailure(); return nil }
                        guard let isDirectory = values.isDirectory else { assertionFailure(); return nil }
                        guard !isDirectory else { return nil }
                        guard let name = values.name, let creationDate = values.creationDate, let fileSize = values.fileSize else { assertionFailure(); return nil }
                        return Item.file(name: name, creationDate: creationDate, byteSize: fileSize, url: url)
                    }
                snapshot.appendItems(items)
            }

            // Apply the snapshot
            
            dataSource.apply(snapshot)
            
        } catch {
            assertionFailure(error.localizedDescription)
        }
    }

    
    // MARK: - UICollectionViewDelegate
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        
        guard let item = self.dataSource.itemIdentifier(for: indexPath) else { return }

        switch item {

        case .directory(name: _, creationDate: _, url: let url):
            let vc = InternalStorageExplorerViewController(root: url)
            navigationController?.pushViewController(vc, animated: true)

        case .file(name: _, creationDate: _, byteSize: _, url: _):
            collectionView.deselectItem(at: indexPath, animated: true)
            
        }
        
        
    }
    
    
    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath], point: CGPoint) -> UIContextMenuConfiguration? {
        guard indexPaths.count == 1, let indexPath = indexPaths.first else { return nil }
        guard let cell = collectionView.cellForItem(at: indexPath) else { return nil }
        
        guard let item = self.dataSource.itemIdentifier(for: indexPath) else { return nil }
        let url = item.url
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        
        
        let actionProvider = makeActionProvider(collectionView, cell: cell, url: url)

        let menuConfiguration = UIContextMenuConfiguration(indexPath: indexPath,
                                                           previewProvider: nil,
                                                           actionProvider: actionProvider)

        return menuConfiguration

    }
    
    
    private func makeActionProvider(_ collectionView: UICollectionView, cell: UICollectionViewCell, url: URL) -> (([UIMenuElement]) -> UIMenu?) {
        return { (suggestedActions) in

            var children = [UIMenuElement]()

            // Share action

            do {
                
                let action = UIAction(title: CommonString.Word.Share) { [weak self] (_) in
                    let ativityController = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                    ativityController.popoverPresentationController?.sourceView = cell
                    self?.present(ativityController, animated: true)
                }
                action.image = UIImage(systemIcon: .squareAndArrowUp)
                children.append(action)

            }
            
            return UIMenu(title: "", image: nil, identifier: nil, options: .displayInline, children: children)
            
        }
    }

}
