import AppKit
import ClaudePaceCore

// Flags for trying things out from a terminal:
//   --print        fetch once, print the bar text and exit (checks the live data path)
//   --print --raw  also print the endpoint's raw JSON (usage numbers only, no credentials)
//   --demo         run the menu bar with fixed numbers and no sign-in needed; nothing is
//                  read from or saved to disk or preferences
//
// For the README images (scripts/screenshots.sh), together with --demo:
//   --render-bar <file.png> [--dark]  draw the bar offscreen to a PNG and exit
//   --screenshot    print where the bar item is on screen, a moment after launch
//   --open-menu     with --screenshot, then open the dropdown
//   --open-options  with --screenshot, then open the Show in Bar menu
//   --light | --dark  with --screenshot, force the look of the menus that open
//   CLAUDEPACE_OPTIONS='{"session":{...},"weekly":{...}}'  use these bar options
let args = Array(CommandLine.arguments.dropFirst())
let arguments = Set(args)
let demo = arguments.contains("--demo")
let demoOptions = ProcessInfo.processInfo.environment["CLAUDEPACE_OPTIONS"]
    .flatMap { try? JSONDecoder().decode(BarOptions.self, from: Data($0.utf8)) }

if arguments.contains("--print") {
    let provider = OAuthLimitsProvider()
    do {
        let raw = try await provider.fetchRaw()
        if arguments.contains("--raw") {
            print(String(decoding: raw, as: UTF8.self))
        }
        let snapshot = try UsageSnapshot.decode(raw)
        let report = UsageReport(snapshot: snapshot, history: SampleHistory.load(), now: Date())
        print(report.barText())
    } catch {
        FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
    exit(0)
}

let app = NSApplication.shared

if let flag = args.firstIndex(of: "--render-bar"), args.indices.contains(flag + 1) {
    app.appearance = NSAppearance(named: arguments.contains("--dark") ? .darkAqua : .aqua)
    do {
        let snapshot = try await DemoLimitsProvider().fetch()
        // Reported at the moment it was taken, so "3h 49m left" is exact.
        let report = UsageReport(snapshot: snapshot, history: SampleHistory(), now: snapshot.fetchedAt)
        let title = BarTitle.make(report.segments(options: demoOptions ?? .default))
        guard let png = BarImage.png(for: title, dark: arguments.contains("--dark")) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: URL(fileURLWithPath: args[flag + 1]))
    } catch {
        FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
    exit(0)
}

app.setActivationPolicy(.accessory)
let controller = StatusController(
    provider: demo ? DemoLimitsProvider() : OAuthLimitsProvider(),
    persistsState: !demo,
    options: demo ? demoOptions : nil)
controller.start()
if demo, arguments.contains("--screenshot") {
    controller.prepareForScreenshot(
        opening: arguments.contains("--open-menu") ? .dropdown
            : arguments.contains("--open-options") ? .showInBar : nil,
        appearance: arguments.contains("--light") ? NSAppearance(named: .aqua)
            : arguments.contains("--dark") ? NSAppearance(named: .darkAqua) : nil)
}
app.run()
