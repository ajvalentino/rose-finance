import AppKit

@main struct AppearanceTests {
    @MainActor static func main() {
        let app = NSApplication.shared
        let choices: [NSAppearance.Name] = [.aqua, .darkAqua]
        app.appearance = nil
        let system = app.effectiveAppearance.bestMatch(from: choices)
        var checks = 0
        func check(_ value: Bool, _ name: String) {
            precondition(value, name); checks += 1
        }
        for mode in [AppAppearance.light, .dark, .light, .dark] {
            mode.apply(to: app)
            let expected: NSAppearance.Name = mode == .light ? .aqua : .darkAqua
            check(app.effectiveAppearance.bestMatch(from: choices) == expected, "Explicit appearance applies")
            AppAppearance.system.apply(to: app)
            check(app.appearance == nil, "System removes the native override")
            check(app.effectiveAppearance.bestMatch(from: choices) == system, "System resolves to OS appearance after override")
        }
        print("Passed \(checks) native appearance transition checks.")
    }
}
