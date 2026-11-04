import Foundation

/// The addresses that open the right app with the text already written. Pure, so what is built can be checked without a phone.
nonisolated enum HandoffURL {
    /// Letters, digits and the unreserved punctuation: everything else is percent-encoded, so a "&" or a line break in a draft can't end
    /// the text early or add a field.
    private static let allowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    static func encode(_ text: String) -> String { text.addingPercentEncoding(withAllowedCharacters: allowed) ?? "" }

    /// A phone number as dialled: digits, with a leading + kept ("+91 98765-43210" → "+919876543210").
    static func dialable(_ number: String) -> String {
        let trimmed = number.trimmingCharacters(in: .whitespaces)
        return (trimmed.hasPrefix("+") ? "+" : "") + trimmed.filter(\.isNumber)
    }

    static func mailto(to: [String], subject: String, body: String) -> URL? {
        let recipients = to.map { encode($0.trimmingCharacters(in: .whitespaces)) }.filter { !$0.isEmpty }.joined(separator: ",")
        var parts: [String] = []
        if !subject.isEmpty { parts.append("subject=\(encode(subject))") }
        if !body.isEmpty { parts.append("body=\(encode(body))") }
        return URL(string: "mailto:\(recipients)" + (parts.isEmpty ? "" : "?" + parts.joined(separator: "&")))
    }

    static func sms(to number: String?, body: String) -> URL? {
        let n = number.map(dialable) ?? ""
        return URL(string: "sms:\(n)" + (body.isEmpty ? "" : "&body=\(encode(body))"))
    }

    /// WhatsApp's own link: with a number it opens that chat, without one it asks who to send to.
    static func whatsApp(to number: String?, text: String) -> URL? {
        let digits = (number.map(dialable) ?? "").filter(\.isNumber)
        return URL(string: "https://wa.me/\(digits)" + (text.isEmpty ? "" : "?text=\(encode(text))"))
    }

    static func tel(_ number: String) -> URL? {
        let n = dialable(number)
        return n.filter(\.isNumber).count >= 3 ? URL(string: "tel:\(n)") : nil
    }
}

/// What opening a message action should do.
nonisolated enum HandoffPlan: Equatable, Sendable {
    /// Mail's composer, shown inside Echo.
    case mailComposer(to: [String], subject: String, body: String)
    /// Messages' composer, shown inside Echo.
    case messageComposer(to: [String], body: String)
    /// Another app, or the system, through an address.
    case open(URL, app: String)
    /// Nothing can be built (no number for a call).
    case unavailable(String)

    var app: String {
        switch self {
        case .mailComposer: "Mail"
        case .messageComposer: "Messages"
        case .open(_, let app): app
        case .unavailable: ""
        }
    }

    /// Picks the in-app composer when the phone can send, and an address otherwise.
    static func message(channel: MessageChannel, to recipient: String, subject: String, body: String, canSendMail: Bool, canSendText: Bool) -> HandoffPlan {
        let who = recipient.trimmingCharacters(in: .whitespaces)
        switch channel {
        case .email:
            if canSendMail { return .mailComposer(to: who.isEmpty ? [] : [who], subject: subject, body: body) }
            return HandoffURL.mailto(to: who.isEmpty ? [] : [who], subject: subject, body: body).map { .open($0, app: "Mail") } ?? .unavailable("Couldn't prepare the email.")
        case .messages:
            if canSendText { return .messageComposer(to: who.isEmpty ? [] : [who], body: body) }
            return HandoffURL.sms(to: who.isEmpty ? nil : who, body: body).map { .open($0, app: "Messages") } ?? .unavailable("Couldn't prepare the message.")
        case .whatsapp:
            return HandoffURL.whatsApp(to: who.isEmpty ? nil : who, text: body).map { .open($0, app: "WhatsApp") } ?? .unavailable("Couldn't prepare the WhatsApp message.")
        }
    }

    static func call(_ number: String) -> HandoffPlan {
        HandoffURL.tel(number).map { .open($0, app: "Phone") } ?? .unavailable("There is no number to call yet. Add one first.")
    }
}
