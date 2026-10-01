import AppKit
import ClaudePaceCore

@MainActor
final class StatusController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let provider: any LimitsProvider
    private let persistsState: Bool
    private let policy = PollPolicy()

    private var state: PollState
    private var history: SampleHistory
    private var lastError: LimitsError?
    private var pollTask: Task<Void, Never>?
    private var tickTimer: Timer?

    private var snapshot: UsageSnapshot? { state.snapshot }

    /// What is wrong right now, if anything. A rate limit that began before a
    /// restart still counts, so the bar stays dimmed until a request succeeds.
    private var problem: LimitsError? {
        lastError ?? (state.rateLimitStreak > 0 ? .rateLimited(retryAfter: nil) : nil)
    }

    private var options: BarOptions {
        didSet {
            if persistsState { options.save() }
            render()
        }
    }

    // Built once and reused: a submenu can hang from only one menu item at a time,
    // and the dropdown itself is rebuilt each time it opens.
    private lazy var showInBar = ShowInBarMenu(
        read: { [unowned self] in self.options },
        write: { [unowned self] in self.options = $0 })

    private lazy var showInBarItem: NSMenuItem = {
        let item = NSMenuItem(title: "Show in Bar", action: nil, keyEquivalent: "")
        item.submenu = showInBar.menu
        return item
    }()

    /// - Parameter persistsState: when false (demo mode) nothing is read from or
    ///   written to disk or preferences, so a demo never touches real settings.
    /// - Parameter options: bar options to start with instead of the saved ones.
    init(provider: any LimitsProvider, persistsState: Bool = true, options: BarOptions? = nil) {
        self.provider = provider
        self.persistsState = persistsState
        self.state = persistsState ? PollState.load() : PollState()
        self.history = persistsState ? SampleHistory.load() : SampleHistory()
        self.options = options ?? (persistsState ? BarOptions.load() : .default)
        super.init()
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
        render()
    }

    func start() {
        pollTask = Task { [weak self] in await self?.pollLoop() }
        // The countdown moves between polls, so the bar is redrawn on its own beat.
        tickTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.render() }
        }
    }

    /// What to open on its own, for documentation screenshots.
    enum ScreenshotTarget {
        case dropdown
        case showInBar
    }

    /// For documentation screenshots. A moment after launch, prints where the bar item
    /// is on screen (`frame x y width height`, in points from the top left, which is
    /// what `screencapture -R` takes), then opens `target` if there is one. macOS does
    /// not attribute menu bar items to the app that owns them, so the app has to say.
    func prepareForScreenshot(
        opening target: ScreenshotTarget?, appearance: NSAppearance? = nil, after delay: TimeInterval = 1
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let button = self.statusItem.button, let frame = button.window?.frame else { return }
                // Menus take their look from the menu itself, not from the app.
                self.statusItem.menu?.appearance = appearance
                self.showInBar.menu.appearance = appearance
                let screenHeight = NSScreen.screens.first?.frame.height ?? 0
                let line = "frame \(Int(frame.minX)) \(Int(screenHeight - frame.maxY)) \(Int(frame.width)) \(Int(frame.height))\n"
                FileHandle.standardOutput.write(Data(line.utf8))

                // Refresh Now is closed for a while after a request; keep it from
                // showing greyed out in the picture.
                self.state.lastAttemptAt = nil

                switch target {
                case nil:
                    break
                case .dropdown?:
                    if let menu = self.statusItem.menu { Self.popUp(menu, near: frame) }
                case .showInBar?:
                    self.showInBar.refresh()
                    Self.popUp(self.showInBar.menu, near: frame)
                }
            }
        }
    }

    /// A menu opens with whatever is under the pointer highlighted, which would show
    /// in the picture. So it opens below the bar item if the pointer is not about to
    /// be over it, and otherwise at the first of a few other places where it is not.
    /// The pointer itself is never moved.
    private static func popUp(_ menu: NSMenu, near itemFrame: NSRect) {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first?.frame ?? .zero
        // Generous room for the tallest menu, so the pointer cannot end up inside it.
        let room = NSSize(width: 440, height: 820)
        let candidates = [itemFrame.minX, 40, screen.maxX - room.width, screen.midX - room.width / 2]
        let x = candidates.first { x in
            !NSRect(x: x - 20, y: itemFrame.minY - room.height, width: room.width + 40, height: room.height + 20)
                .contains(pointer)
        } ?? candidates[0]
        // The top of the usable area is the bottom edge of the menu bar. Opening any
        // higher puts the top of the menu under the bar and macOS clips it.
        let top = (NSScreen.screens.first?.visibleFrame.maxY ?? itemFrame.minY) - 4
        menu.popUp(positioning: nil, at: NSPoint(x: x, y: top), in: nil)
    }

    // MARK: Polling

    private func pollLoop() async {
        while !Task.isCancelled {
            // The saved schedule is honoured first, so reopening the app never
            // costs a request. It is re-read after every sleep because a manual
            // refresh moves it.
            while let due = state.nextAttemptAt, due.timeIntervalSinceNow > 0 {
                try? await Task.sleep(for: .seconds(due.timeIntervalSinceNow))
                if Task.isCancelled { return }
            }
            await poll()
        }
    }

    private func poll() async {
        state.lastAttemptAt = Date()
        do {
            let fresh = try await provider.fetch()
            state.snapshot = fresh
            state.rateLimitStreak = 0
            state.nextAttemptAt = Date().addingTimeInterval(policy.successInterval)
            lastError = nil
            record(fresh)
        } catch {
            let failure = (error as? LimitsError) ?? .network(error.localizedDescription)
            lastError = failure
            if case .rateLimited = failure { state.rateLimitStreak += 1 }
            let wait = policy.delay(after: failure, rateLimitStreak: state.rateLimitStreak)
            state.nextAttemptAt = Date().addingTimeInterval(wait)
        }
        if persistsState { state.save() }
        render()
    }

    private func record(_ snapshot: UsageSnapshot) {
        if let window = snapshot.fiveHour {
            history.record(.session, utilization: window.utilization, at: snapshot.fetchedAt)
        }
        if let window = snapshot.sevenDay {
            history.record(.weekly, utilization: window.utilization, at: snapshot.fetchedAt)
        }
        if persistsState { history.save() }
    }

    // MARK: Menu bar title

    private func currentReport() -> UsageReport? {
        snapshot.map { UsageReport(snapshot: $0, history: history, now: Date()) }
    }

    private func render() {
        guard let button = statusItem.button else { return }
        let font = NSFont.menuBarFont(ofSize: 0)
        let dim: CGFloat = problem == nil ? 1 : 0.6

        let segments = currentReport()?.segments(options: options) ?? []
        guard !segments.isEmpty else {
            let text = problem == nil ? "Pace …" : "Pace ⚠︎"
            button.attributedTitle = NSAttributedString(
                string: text, attributes: [.font: font, .foregroundColor: NSColor.labelColor.withAlphaComponent(dim)])
            return
        }

        button.attributedTitle = BarTitle.make(segments, font: font, dim: dim)
    }

    // MARK: Dropdown

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if let report = currentReport() {
            if let session = report.session { addDetails(to: menu, session, heading: "Session (5 hours)") }
            if let weekly = report.weekly { addDetails(to: menu, weekly, heading: "Total (7 days)") }
            if report.sonnet != nil || report.opus != nil {
                menu.addItem(.separator())
                if let sonnet = report.sonnet { menu.addItem(info("Sonnet, 7 days: \(Int(sonnet.utilization.rounded()))%")) }
                if let opus = report.opus { menu.addItem(info("Opus, 7 days: \(Int(opus.utilization.rounded()))%")) }
            }
            menu.addItem(.separator())
        }

        if let problem {
            menu.addItem(info(problem.localizedDescription))
        } else if let snapshot {
            menu.addItem(info("Updated \(snapshot.fetchedAt.formatted(date: .omitted, time: .standard))"))
        } else {
            menu.addItem(info("Loading…"))
        }
        if let next = state.nextAttemptAt, next > Date() {
            menu.addItem(info("Next check at \(next.formatted(date: .omitted, time: .shortened))"))
        }

        let refresh = action("Refresh Now", #selector(refreshNow), key: "r")
        refresh.isEnabled = state.canRefreshManually(now: Date(), policy: policy)
        menu.addItem(refresh)

        showInBar.refresh()
        menu.addItem(showInBarItem)
        menu.addItem(.separator())
        menu.addItem(action("Quit Claude Pace", #selector(quit), key: "q"))
    }

    private func addDetails(to menu: NSMenu, _ report: WindowReport, heading: String) {
        menu.addItem(MenuItems.heading(heading + " - \(report.percentText) used"))
        guard let estimate = report.estimate, let resetsAt = report.window.resetsAt else { return }
        menu.addItem(info("Resets \(resetsAt.formatted(date: .abbreviated, time: .shortened)) (in \(DurationFormat.left(estimate.remaining)))"))
        menu.addItem(info("At this pace: ~\(min(999, Int(estimate.projectedAtReset.rounded())))% by reset"))
        if let toLimit = estimate.timeToLimit {
            menu.addItem(info("Limit reached in \(DurationFormat.left(toLimit)), before the reset"))
        }
        menu.addItem(info("Verdict: \(estimate.verdict.label)"))
        menu.addItem(.separator())
    }

    private func info(_ text: String) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, _ selector: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func refreshNow() {
        guard state.canRefreshManually(now: Date(), policy: policy) else { return }
        Task { await poll() }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
