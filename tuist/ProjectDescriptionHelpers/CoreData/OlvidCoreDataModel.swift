import ProjectDescription

public enum OlvidCoreDataModel {
    
    case app
    case engine
    case userNotification
    case backup
    
    fileprivate var coreDataModel: CoreDataModel {
        let path: Path
        switch self {
        case .app:
            path = Path.olvidPath("ObvAppDatabase/Sources/ObvMessenger.xcdatamodeld", in: .app)
        case .engine:
            path = Path.olvidPath("ObvDatabaseManager/Sources/ObvEngine.xcdatamodeld", in: .engine)
        case .userNotification:
            path = Path.olvidPath("ObvUserNotifications/Database/Sources/ObvUserNotificationsDataModel.xcdatamodeld", in: .app)
        case .backup:
            path = Path.olvidPath("ObvBackupManagerNew/Sources/CoreData/ObvBackupManagerModel.xcdatamodeld", in: .engine)
        }
        return .coreDataModel(path)
    }
    
}


public extension CoreDataModel {
    
    static func olvidCoreDataModel(_ olvidCoreDataModel: OlvidCoreDataModel) -> Self {
        olvidCoreDataModel.coreDataModel
    }
    
}
