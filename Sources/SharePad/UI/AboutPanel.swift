import AppKit

enum AboutPanel {
    private static let repo = "https://github.com/jonyardley/SharePad"
    private static let issues = "https://github.com/jonyardley/SharePad/issues"
    private static let tagline =
        "Turn a USB-connected iPad into an always-ready window for any video call."

    static func present() {
        // As an LSUIElement agent app the panel can open behind the frontmost
        // window; activate so it comes forward.
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    private static var credits: NSAttributedString {
        let body = NSMutableAttributedString(
            string: tagline + "\n\n",
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        body.append(link("GitHub", url: repo))
        body.append(separator)
        body.append(link("Report an Issue", url: issues))

        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        body.addAttribute(
            .paragraphStyle,
            value: centered,
            range: NSRange(location: 0, length: body.length)
        )
        return body
    }

    private static func link(_ text: String, url: String) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .link: url,
            ]
        )
    }

    private static var separator: NSAttributedString {
        NSAttributedString(
            string: "  ·  ",
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
    }
}
