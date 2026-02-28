import Cocoa

class PermanentStorage {
  private static func bool(forKey key: StorageKey, withDefault defaultValue: Bool) -> Bool {
    if UserDefaults.standard.object(forKey: key.rawValue) != nil {
      return UserDefaults.standard.bool(forKey: key.rawValue)
    }
    return defaultValue
  }

  private static func set(_ value: Bool, forKey key: StorageKey) {
    UserDefaults.standard.set(value, forKey: key.rawValue)
  }

  private enum StorageKey: String {
    case showsNotification = "show-notification"
    case launchedForTheFirstTime = "launched-for-the-first-time"
    case modifierToggleEnabled = "modifier-toggle-enabled"
    case shiftSpaceToggleEnabled = "shift-space-toggle-enabled"
  }

  static var showsNotification: Bool {
    get {
      return bool(forKey: .showsNotification, withDefault: false)
    }
    set {
      set(newValue, forKey: .showsNotification)
    }
  }

  static var launchedForTheFirstTime: Bool {
    get {
      return bool(forKey: .launchedForTheFirstTime, withDefault: true)
    }
    set {
      set(newValue, forKey: .launchedForTheFirstTime)
    }
  }

  static var modifierToggleEnabled: Bool {
    get {
      return bool(forKey: .modifierToggleEnabled, withDefault: true)
    }
    set {
      set(newValue, forKey: .modifierToggleEnabled)
    }
  }

  static var shiftSpaceToggleEnabled: Bool {
    get {
      return bool(forKey: .shiftSpaceToggleEnabled, withDefault: true)
    }
    set {
      set(newValue, forKey: .shiftSpaceToggleEnabled)
    }
  }
}
