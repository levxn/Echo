import MessageUI
import SwiftUI

/// What the person did in the system composer.
enum ComposeOutcome { case sent, saved, cancelled, failed }

/// Mail's own composer, shown inside Echo, with the recipient, subject and text already filled in. The person presses Send there.
struct MailComposer: UIViewControllerRepresentable {
    let to: [String]
    let subject: String
    let body: String
    let onFinish: (ComposeOutcome) -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients(to)
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        return vc
    }

    func updateUIViewController(_ vc: MFMailComposeViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onFinish) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: (ComposeOutcome) -> Void
        init(_ onFinish: @escaping (ComposeOutcome) -> Void) { self.onFinish = onFinish }
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            onFinish(error != nil ? .failed : (result == .sent ? .sent : (result == .saved ? .saved : .cancelled)))
        }
    }
}

/// Messages' own composer, shown inside Echo.
struct MessageComposer: UIViewControllerRepresentable {
    let to: [String]
    let body: String
    let onFinish: (ComposeOutcome) -> Void

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let vc = MFMessageComposeViewController()
        vc.messageComposeDelegate = context.coordinator
        vc.recipients = to
        vc.body = body
        return vc
    }

    func updateUIViewController(_ vc: MFMessageComposeViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onFinish) }

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let onFinish: (ComposeOutcome) -> Void
        init(_ onFinish: @escaping (ComposeOutcome) -> Void) { self.onFinish = onFinish }
        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            onFinish(result == .sent ? .sent : (result == .failed ? .failed : .cancelled))
        }
    }
}

enum ComposerSupport {
    static var canSendMail: Bool { MFMailComposeViewController.canSendMail() }
    static var canSendText: Bool { MFMessageComposeViewController.canSendText() }
}
