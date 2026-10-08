// Where `AppModel` keeps its settings: the app's `UserDefaults`, or a test's own store.
import Foundation

protocol SettingsStore: AnyObject {
    func string(forKey key: String) -> String?
    func bool(forKey key: String) -> Bool
    func data(forKey key: String) -> Data?
    func dictionary(forKey key: String) -> [String: Any]?
    func set(_ value: Any?, forKey key: String)
}

extension UserDefaults: SettingsStore {}
