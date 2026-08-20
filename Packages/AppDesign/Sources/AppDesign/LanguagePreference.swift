import SwiftUI
import ObjectiveC

private let languageKey = "com.tasktracker.language"

@MainActor
@Observable
public final class LanguagePreference {
    static public let shared = LanguagePreference()
    static public let storageKey = languageKey

    public var selectedLanguageCode: String? {
        didSet { UserDefaults.standard.set(selectedLanguageCode, forKey: languageKey) }
    }

    private init() {
        selectedLanguageCode = UserDefaults.standard.string(forKey: languageKey)
    }

    public func apply() {
        Self.swizzleIfNeeded()
        UserDefaults.standard.set(selectedLanguageCode, forKey: languageKey)
    }

    private static var hasSwizzled = false
    private static var originalIMP: IMP?

    private static func swizzleIfNeeded() {
        guard !hasSwizzled else { return }
        hasSwizzled = true

        let cls: AnyClass = Bundle.self
        let sel = NSSelectorFromString("main")

        guard let method = class_getClassMethod(cls, sel) else { return }

        originalIMP = method_getImplementation(method)

        let capturedIMP = originalIMP!
        let newIMP: IMP = imp_implementationWithBlock({ (_: AnyClass) -> Bundle in
            let fn = unsafeBitCast(capturedIMP, to: (@convention(c) (AnyClass, Selector) -> Bundle).self)
            let base = fn(cls, sel)

            if let code = UserDefaults.standard.string(forKey: languageKey),
               let bundle = LanguageBundle(base: base, languageCode: code) {
                return bundle
            }
            return base
        }) as IMP

        method_setImplementation(method, newIMP)
    }
}

public enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case en
    case tr
    case ar

	public var id: String { rawValue }

    public var label: String {
        switch self {
        case .system: return "Automatic"
        case .en:     return "English"
        case .tr:     return "Türkçe"
        case .ar:     return "العربية"
        }
    }

    public var languageCode: String? {
        switch self {
        case .system: return nil
        default:      return rawValue
        }
    }
}

private final class LanguageBundle: Bundle {
    private let langCode: String

    init?(base: Bundle, languageCode: String) {
        self.langCode = languageCode
        super.init(path: base.bundlePath)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let path = path(forResource: langCode, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}
