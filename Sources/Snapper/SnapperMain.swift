import AppKit

@main
enum SnapperMain {
    static func main() async {
        // Headless pipeline check, kept off the GUI path so it can be run from a
        // terminal on a machine that has granted Screen Recording access.
        if CommandLine.arguments.contains("--diagnose") {
            await DiagnosticReport.run()
            return
        }

        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
