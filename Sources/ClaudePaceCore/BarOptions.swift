import Foundation

/// The details a bar segment can show. The order here is the order they appear in
/// the bar and in the menu; the keyword always comes last, after a divider.
public enum BarField: String, CaseIterable, Codable, Sendable {
    case percent
    case timeLeft
    /// How long until the limit is reached at the current pace. Only there while
    /// the limit would be reached before the reset.
    case limitIn
    case keyword

    public var menuTitle: String {
        switch self {
        case .percent: "Percentage"
        case .timeLeft: "Time left"
        case .limitIn: "Time to limit"
        case .keyword: "Pace keyword"
        }
    }
}

/// What the bar shows for one window (Session or Total). Each window has its own.
public struct WindowOptions: Equatable, Codable, Sendable {
    /// Whether this window appears in the bar at all.
    public var isShown: Bool
    /// Whether its segment starts with the window's name ("Session", "Total").
    public var showsLabel: Bool
    /// Never empty: a window with nothing to show would be a bare name.
    public var fields: Set<BarField>

    /// What a window shows until its options are changed. "Time to limit" is opt-in
    /// because the bar is already long.
    public static let defaultFields: Set<BarField> = [.percent, .timeLeft, .keyword]

    public init(isShown: Bool = true, showsLabel: Bool = true, fields: Set<BarField> = WindowOptions.defaultFields) {
        self.isShown = isShown
        self.showsLabel = showsLabel
        self.fields = fields
    }

    /// The last ticked detail stays ticked.
    public mutating func toggle(_ field: BarField) {
        if fields.contains(field) {
            if fields.count > 1 { fields.remove(field) }
        } else {
            fields.insert(field)
        }
    }

    public func canTurnOff(_ field: BarField) -> Bool { !fields.contains(field) || fields.count > 1 }
}

/// What the menu bar shows: for each window, whether it appears and which details.
public struct BarOptions: Equatable, Codable, Sendable {
    public var session: WindowOptions
    public var weekly: WindowOptions

    public static let `default` = BarOptions()

    public init(session: WindowOptions = WindowOptions(), weekly: WindowOptions = WindowOptions()) {
        self.session = session
        self.weekly = weekly
    }

    /// The same details for every window in `windows`, and the rest hidden. This is
    /// also how settings saved before windows had their own switches are read.
    public init(windows: Set<LimitKind>, fields: Set<BarField>, showsLabel: Bool = true) {
        func options(_ kind: LimitKind) -> WindowOptions {
            WindowOptions(isShown: windows.contains(kind), showsLabel: showsLabel, fields: fields)
        }
        self.init(session: options(.session), weekly: options(.weekly))
    }

    public subscript(kind: LimitKind) -> WindowOptions {
        get {
            switch kind {
            case .session: session
            case .weekly: weekly
            }
        }
        set {
            switch kind {
            case .session: session = newValue
            case .weekly: weekly = newValue
            }
        }
    }

    /// At least one window stays in the bar so it can never go blank.
    public mutating func toggleShown(_ kind: LimitKind) {
        guard !self[kind].isShown || canHide(kind) else { return }
        self[kind].isShown.toggle()
    }

    public func canHide(_ kind: LimitKind) -> Bool {
        !self[kind].isShown || LimitKind.allCases.filter { self[$0].isShown }.count > 1
    }

    private enum CodingKeys: String, CodingKey {
        case session, weekly
        // Only read, from settings saved when all windows shared one set of details.
        case windows, fields, showsLabel
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let session = try container.decodeIfPresent(WindowOptions.self, forKey: .session),
           let weekly = try container.decodeIfPresent(WindowOptions.self, forKey: .weekly) {
            self.init(session: session, weekly: weekly)
        } else {
            self.init(
                windows: try container.decode(Set<LimitKind>.self, forKey: .windows),
                fields: try container.decode(Set<BarField>.self, forKey: .fields),
                showsLabel: try container.decodeIfPresent(Bool.self, forKey: .showsLabel) ?? true)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(session, forKey: .session)
        try container.encode(weekly, forKey: .weekly)
    }
}

extension BarOptions {
    private static let defaultsKey = "barOptions"

    /// Anything unreadable gives the defaults; a half-empty saved choice is repaired
    /// so the bar cannot come up blank.
    public static func load(from defaults: UserDefaults = .standard) -> BarOptions {
        guard let data = defaults.data(forKey: defaultsKey),
              var stored = try? JSONDecoder().decode(BarOptions.self, from: data)
        else { return .default }
        for kind in LimitKind.allCases where stored[kind].fields.isEmpty {
            stored[kind].fields = WindowOptions.defaultFields
        }
        if LimitKind.allCases.allSatisfy({ !stored[$0].isShown }) {
            for kind in LimitKind.allCases { stored[kind].isShown = true }
        }
        return stored
    }

    public func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
