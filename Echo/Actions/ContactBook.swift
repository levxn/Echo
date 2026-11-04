import Contacts
import Foundation

/// What Echo needs to know about a person to address something to them. Looked up on the phone and never sent anywhere.
nonisolated struct ContactCard: Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var emails: [String]
    var phones: [String]
}

/// Matches a spoken name ("Ravi", "Mr. Brennan", "Grandma") against the contacts, best match first. Pure.
nonisolated enum ContactMatcher {
    private static let titles: Set<String> = ["mr", "mister", "mrs", "missus", "ms", "miss", "dr", "doctor", "prof", "professor"]

    private static func tokens(_ s: String) -> [String] {
        s.lowercased().split(whereSeparator: { !$0.isLetter && $0 != "’" && $0 != "'" }).map { String($0).replacingOccurrences(of: "’s", with: "").replacingOccurrences(of: "'s", with: "") }
            .filter { !titles.contains($0) && !$0.isEmpty }
    }

    static func matches(_ name: String, in cards: [ContactCard]) -> [ContactCard] {
        let wanted = tokens(name)
        guard !wanted.isEmpty else { return [] }
        let scored: [(ContactCard, Int)] = cards.compactMap { card in
            let have = tokens(card.name)
            guard !have.isEmpty else { return nil }
            if have == wanted { return (card, 3) }                                   // the whole name
            if wanted.count == 1, have.first == wanted[0] || have.last == wanted[0] { return (card, 2) }   // just the first or the last name
            if wanted.allSatisfy(have.contains) { return (card, 1) }                 // every spoken word is in the name
            return nil
        }
        return scored.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.name < $1.0.name }.map(\.0)
    }
}

/// The address book, behind a small interface so tests don't need it.
@MainActor
protocol ContactResolving: AnyObject {
    /// The contacts that could be this person. Asks permission the first time; empty if it is refused.
    func resolve(name: String) async -> [ContactCard]
}

final class SystemContacts: ContactResolving {
    private let store = CNContactStore()

    func resolve(name: String) async -> [ContactCard] {
        do { guard try await store.requestAccess(for: .contacts) else { return [] } } catch { return [] }
        let keys: [CNKeyDescriptor] = [CNContactGivenNameKey as CNKeyDescriptor, CNContactFamilyNameKey as CNKeyDescriptor, CNContactNicknameKey as CNKeyDescriptor,
                                       CNContactEmailAddressesKey as CNKeyDescriptor, CNContactPhoneNumbersKey as CNKeyDescriptor]
        var cards: [ContactCard] = []
        let request = CNContactFetchRequest(keysToFetch: keys)
        try? store.enumerateContacts(with: request) { contact, _ in
            let full = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
            for label in [full, contact.nickname] where !label.isEmpty {
                cards.append(ContactCard(id: contact.identifier + (label == full ? "" : "#nick"), name: label, emails: contact.emailAddresses.map { String($0.value) },
                                         phones: contact.phoneNumbers.map { $0.value.stringValue }))
            }
        }
        return ContactMatcher.matches(name, in: cards)
    }
}
