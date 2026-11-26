/// Which edition is being built.
///
/// Without the `FULL_EDITION` compilation condition (the default, and the App Store build) the code that reads other
/// apps' data – WhatsApp and Signal chats, Safari and Firefox history, Safari bookmarks – is not compiled at all,
/// so it is not part of the shipped app. A direct-download edition can add `FULL_EDITION` to
/// `SWIFT_ACTIVE_COMPILATION_CONDITIONS` to bring it back.
enum Edition {
    #if FULL_EDITION
    static let readsOtherAppsData = true
    #else
    static let readsOtherAppsData = false
    #endif
}
