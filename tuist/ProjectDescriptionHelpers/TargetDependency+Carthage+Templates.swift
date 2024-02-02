import ProjectDescription
import Foundation


public extension TargetDependency {
    
    enum CarthageDependency: CaseIterable {
        
        /// https://gitlab.com/Olvid/appauthiosmodifiedforolvid/-/tree/modified-for-olvid
        //case appAuth
        
        //case joseSwift

        public var dependency: CarthageDependencies.Dependency {
            switch self {
//            case .appAuth:
//                // WARNING: When changing this, we must delete the Dependencies directory manually
//                return .github(path: "https://github.com/openid/AppAuth-iOS", requirement: .exact(.init(1, 6, 2)))
//                //return .github(path: "https://github.com/olvid-io/AppAuth-iOS-for-Olvid.git", requirement: .branch("targetfix"))
////            case .joseSwift:
////                return .github(path: "https://github.com/olvid-io/JOSESwift-for-Olvid", requirement: .branch("targetfix"))
////                // return .github(path: "https://github.com/airsidemobile/JOSESwift.git", requirement: .exact(.init(2, 4, 0)))

            }
        }

        fileprivate var _productName: String {
            switch self {
//            case .appAuth:
//                return "AppAuth"
//            case .joseSwift:
//                return "JOSESwift"
            }
        }
    }
    
}


public extension TargetDependency {
    
    init(_ carthageDependency: CarthageDependency) {
        self = .external(name: carthageDependency._productName)
    }
    
}


extension CarthageDependencies {
    
    public init(_ dependencies: [TargetDependency.CarthageDependency]) {
    
        let targetDependencies: [CarthageDependencies.Dependency] = dependencies
            .map(\.dependency)

        self.init(targetDependencies)
        
    }
    
}
