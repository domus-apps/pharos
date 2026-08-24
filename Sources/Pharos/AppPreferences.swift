import Foundation

/* App-level preferences. Same UserDefaults caveat as the rest of the app:
   `swift run` and the bundled app use different defaults domains. */
enum AppPreferences {
    static let changed = Notification.Name("Pharos.PreferencesChanged")

    private static let hideMenuBarIconKey = "pref.hideMenuBarIcon"
    private static let keepDisplayAwakeKey = "pref.keepDisplayAwake"
    private static let activateOnLaunchKey = "pref.activateOnLaunch"
    private static let menuBarIconStyleKey = "pref.menuBarIconStyle"

    static var isMenuBarIconHidden: Bool {
        get { UserDefaults.standard.bool(forKey: hideMenuBarIconKey) }
        set { set(newValue, forKey: hideMenuBarIconKey) }
    }

    /* Off: only system sleep is prevented — the display may still dim,
       sleep, and lock. On (the default): the display stays awake too. A dark,
       locked screen is indistinguishable from a sleeping Mac, so keeping the
       display on is what "keep awake" means to most people. */
    static var keepsDisplayAwake: Bool {
        get { UserDefaults.standard.object(forKey: keepDisplayAwakeKey) as? Bool ?? true }
        set { set(newValue, forKey: keepDisplayAwakeKey) }
    }

    static var activatesOnLaunch: Bool {
        get { UserDefaults.standard.bool(forKey: activateOnLaunchKey) }
        set { set(newValue, forKey: activateOnLaunchKey) }
    }

    /* Falls back to the classic beacon for unset or unrecognized values
       (e.g. a style removed in a future version). */
    static var menuBarIconStyle: MenuBarIconStyle {
        get {
            UserDefaults.standard.string(forKey: menuBarIconStyleKey)
                .flatMap(MenuBarIconStyle.init(rawValue:)) ?? .beacon
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: menuBarIconStyleKey)
            NotificationCenter.default.post(name: changed, object: nil)
        }
    }

    private static func set(_ value: Bool, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
        NotificationCenter.default.post(name: changed, object: nil)
    }
}
