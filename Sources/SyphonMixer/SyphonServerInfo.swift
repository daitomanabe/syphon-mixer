import Foundation
import Syphon

struct SyphonServerInfo {
    var id: String
    var displayName: String
    var serverName: String
    var appName: String
    var description: [String: Any]
}

enum SyphonServerFormatter {
    static func info(from description: [String: Any]) -> SyphonServerInfo? {
        let serverName = description[SyphonServerDescriptionNameKey] as? String ?? "Untitled"
        let appName = description[SyphonServerDescriptionAppNameKey] as? String ?? "Unknown App"
        let uuid = description[SyphonServerDescriptionUUIDKey] as? String
        let id = uuid ?? "\(appName)::\(serverName)"
        let displayName = appName == "Unknown App" ? serverName : "\(appName) / \(serverName)"

        return SyphonServerInfo(
            id: id,
            displayName: displayName,
            serverName: serverName,
            appName: appName,
            description: description
        )
    }
}
