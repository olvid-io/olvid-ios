import ProjectDescription
import Foundation

let xcodeVersionFileVersion = try! {
    let currentPath = (#file as NSString).deletingLastPathComponent

    let xcodesVersionFilePath = (currentPath.appending("/../.xcode-version") as NSString)
        .resolvingSymlinksInPath

    guard FileManager.default.fileExists(atPath: xcodesVersionFilePath) else {
        fatalError("expected \(xcodesVersionFilePath) to exist")
    }

    return try String(contentsOfFile: xcodesVersionFilePath)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}()

let config = Config(
    //compatibleXcodeVersions: .exact(.init(stringLiteral: xcodeVersionFileVersion)),
    compatibleXcodeVersions: .all,
    generationOptions: .options(resolveDependenciesWithSystemScm: true)
)
