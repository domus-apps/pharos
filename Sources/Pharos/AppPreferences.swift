import Foundation

/* App-level preferences. Same UserDefaults caveat as the rest of the app:
   `swift run` and the bundled app use different defaults domains. */
enum AppPreferences {
    static let changed = Notification.Name("Pharos.PreferencesChanged")

    private static let hideMenuBarIconKey = "pref.hideMenuBarIcon"
    private static let keepDisplayAwakeKey = "pref.keepDisplayAwake"
    private static let activateOnLaunchKey = "pref.activateOnLaunch"

    static var isMenuBarIconHidden: Bool {
        get { UserDefaults.standard.bool(forKey: hideMenuBarIconKey) }
        set { set(newValue, forKey: hideMenuBarIconKey) }
    }

    /* Off: only system sleep is prevented — the display may still dim,
       sleep, and lock. On: the display stays awake too. */
    static var keepsDisplayAwake: Bool {
        get { UserDefaults.standard.bool(forKey: keepDisplayAwakeKey) }
        set { set(newValue, forKey: keepDisplayAwakeKey) }
    }

    static var activatesOnLaunch: Bool {
        get { UserDefaults.standard.bool(forKey: activateOnLaunchKey) }
        set { set(newValue, forKey: activateOnLaunchKey) }
    }

    private static func set(_ value: Bool, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
        NotificationCenter.default.post(name: changed, object: nil)
    }
}
