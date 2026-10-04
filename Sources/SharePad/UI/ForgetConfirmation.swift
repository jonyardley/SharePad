import AppKit

@MainActor
enum ForgetConfirmation {
    static func confirm(name: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Forget \(name)?"
        alert.informativeText = """
        It stops connecting over Wi-Fi. To use it again, pair it from SharePad's menu.
        """
        alert.alertStyle = .warning
        let forget = alert.addButton(withTitle: "Forget")
        forget.hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        alert.window.sharingType = .none
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }
}
