import Foundation
import Testing
@testable import Echo

private struct TranscriptRow: Decodable { let transcript: String }
private let projectRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
private func demoTranscripts() throws -> [String] {
    try JSONDecoder().decode([TranscriptRow].self, from: Data(contentsOf: projectRoot.appending(path: "EchoTests/Fixtures/demo_transcripts.json"))).map(\.transcript)
}

struct ConfidentialScannerTests {
    private func kinds(_ text: String) -> [ConfidentialKind] { ConfidentialScanner.scan(text).map(\.kind) }
    private func found(_ text: String) -> [String] { ConfidentialScanner.scan(text).map(\.text) }
    private func redacted(_ text: String) -> String { ConfidentialScanner.redact([text]).texts[0] }

    // MARK: What is caught

    @Test(arguments: [
        ("My password is hunter2, and I will send it later.", "hunter2"),
        ("The wifi password is correct horse battery staple.", "correct horse battery staple"),
        ("Use the password Summer2024 for the portal.", "Summer2024"),
        ("my passphrase: blue-elephant-42", "blue-elephant-42"),
        ("The password for the router is tango7dollar.", "tango7dollar"),
    ])
    func passwordsInTheWaysPeopleSayThem(_ text: String, _ secret: String) {
        #expect(found(text) == [secret], "\(text)")
        #expect(kinds(text) == [.password])
        #expect(!redacted(text).contains(secret))
    }

    @Test(arguments: [
        ("My PIN is 4821.", ConfidentialKind.pin, "4821"), ("The pin code is four eight two one.", .pin, "four eight two one"),
        ("pin number: 4 8 2 1", .pin, "4 8 2 1"), ("The code is 482913.", .code, "482913"), ("Your OTP is 123456", .code, "123456"),
        ("The verification code is 998877, don't share it.", .code, "998877"), ("My CVV is 123.", .code, "123"),
        ("security code: 4 4 1 9", .code, "4 4 1 9"),
    ])
    func pinsAndOneTimeCodes(_ text: String, _ kind: ConfidentialKind, _ value: String) {
        #expect(kinds(text) == [kind], "\(text)")
        #expect(found(text) == [value], "\(text)")
        #expect(!redacted(text).contains(value), "the value is replaced in: \(redacted(text))")
    }

    @Test func cardNumbersAreCaughtOnlyWhenTheyAreCardNumbers() {
        #expect(kinds("Pay with 4111 1111 1111 1111 please") == [.card])
        #expect(kinds("it's 4242-4242-4242-4242") == [.card])
        #expect(kinds("The reference is 1234 5678 9012 3456") == [], "sixteen digits that fail the Luhn check are not a card")
        #expect(found("Pay with 4111 1111 1111 1111 please") == ["4111 1111 1111 1111"])
    }

    @Test(arguments: [
        ("Send it to GB82WEST12345698765432 today.", ConfidentialKind.account), ("My account number is 12345678.", .account),
        ("routing number: 021000021", .account), ("The IFSC is HDFC0001234 for that branch", .account),
        ("My social security number is 123-45-6789.", .id), ("aadhaar number is 1234 5678 9012", .id),
        ("PAN is ABCDE1234F", .id), ("passport number is K1234567", .id),
    ])
    func bankDetailsAndGovernmentIDs(_ text: String, _ kind: ConfidentialKind) {
        #expect(kinds(text).contains(kind), "\(text) → \(kinds(text))")
    }

    @Test(arguments: [
        "My API key is sk-live-abcdefghijklmnop1234", "The token is ghp_abcdefghijklmnopqrstuvwx1234", "send Bearer abcdefghijklmnopqrstu12345 along",
        "the client secret is q8Zr2LmN4tYbXc7WpVd9",
    ])
    func apiKeysAndTokens(_ text: String) {
        #expect(kinds(text).contains(.key), "\(text) → \(found(text))")
    }

    @Test func emailAddressesAndPhoneNumbersAreHeldBackToo() {
        #expect(found("write to ravi.k@example.com about it") == ["ravi.k@example.com"])
        #expect(kinds("ravi at example dot com is his email") == [.email])
        #expect(kinds("Call me on +91 98765 43210 tomorrow") == [.phone])
        #expect(kinds("Her number is (555) 123-4567.") == [.phone])
        #expect(kinds("text 9876543210 when you land") == [.phone])
        #expect(kinds("it is nine eight seven six five four three two one zero") == [.phone], "spoken digits count too")
    }

    // MARK: What is left alone

    @Test(arguments: [
        "I will send you the API specification by Wednesday noon, that's a promise.",
        "The migration is done in staging. I think we can deploy to production on Thursday morning.",
        "I can offer a twelve month renewal, with a four percent rent increase.",
        "Meet at 10:30 on 2024-11-04 in room 204.", "The invoice is 4500 dollars, due November 20th.", "Version 2.0.1 ships on the 15th.",
        "I need two or three of those, one for each.", "Oh, that's good. Pair it with a voucher for a beginner workshop.",
        "The pin on the map is near the Alfama district.", "I forgot my password manager at home.", "It was a code review, nothing more.",
        "We need eggs, olive oil, and oranges for the juice.", "Your mother's birthday is on November fourteenth.",
        "Call her office tomorrow morning and book an appointment.", "That's about 2 or 3 percent, give or take.",
    ])
    func ordinarySentencesAreNotTouched(_ text: String) {
        #expect(found(text) == [], "false positive in: \(text) → \(found(text))")
        #expect(redacted(text) == text)
    }

    @Test func noneOfTheDemoConversationsLooksConfidential() throws {
        let hits = try demoTranscripts().flatMap { t in found(t).map { "\($0) in “\(t)”" } }
        #expect(hits.isEmpty, "\(hits)")
    }

    // MARK: Placeholders

    @Test func placeholdersAreNumberedInReadingOrderAndSharedByEqualValues() {
        let (texts, mask) = ConfidentialScanner.redact([
            "Question: what was the code 482913 for?",
            "My password is hunter2. The code is 482913 and the backup code is 777111.",
            "Email ravi@example.com or ravi@example.com, my password is hunter2.",
        ])
        #expect(texts[0] == "Question: what was the code [CODE_1] for?")
        #expect(texts[1].contains("[PASSWORD_1]") && texts[2].contains("[PASSWORD_1]"), "the same password has the same placeholder: \(texts)")
        #expect(texts[2].components(separatedBy: "[EMAIL_1]").count == 3, "one placeholder for one address, used twice: \(texts[2])")
        #expect(mask.entries.filter { $0.kind == .password }.count == 1)
        #expect(mask.heldBack[.password] == 1 && mask.heldBack[.email] == 1 && (mask.heldBack[.code] ?? 0) >= 1)
        for text in texts { #expect(!text.contains("hunter2") && !text.contains("ravi@example.com") && !text.contains("482913")) }
    }

    @Test func theRealValuesComeBackOnlyWhenAskedAndTolerateSloppyPlaceholders() {
        let (texts, mask) = ConfidentialScanner.redact(["My password is hunter2 and my pin is 4821."])
        #expect(texts[0] == "My password is [PASSWORD_1] and my pin is [PIN_1].")
        #expect(mask.restore("Hi, the password [PASSWORD_1] and pin [pin_1].") == "Hi, the password hunter2 and pin 4821.")
        #expect(mask.restore("see PASSWORD_1 and [ PIN 1 ]") == "see hunter2 and 4821")
        #expect(mask.restore("a [PASSWORD_9] this request never used") == "a [PASSWORD_9] this request never used")
        #expect(SecretMask().restore("[PASSWORD_1]") == "[PASSWORD_1]")
    }

    @Test func theSummaryIsWordedForPeople() {
        let (_, mask) = ConfidentialScanner.redact(["My password is hunter2, my card is 4111 1111 1111 1111, call 9876543210 or 9123456780."])
        #expect(mask.summary == "a password, a card number and 2 phone numbers")
        #expect(SecretMask().summary == "")
        #expect(ConfidentialKind.summary(stored: ["password": 1]) == "a password")
        #expect(ConfidentialKind.summary(stored: ["nonsense": 3]) == "")
    }

    // MARK: Speed

    @Test func aWholeDaysSnippetsAreScannedQuickly() throws {
        let fixture = try demoTranscripts()
        let many = (0..<200).map { fixture[$0 % fixture.count] } + ["My password is hunter2 and the code is 482913."]
        let clock = ContinuousClock()
        let start = clock.now
        let result = ConfidentialScanner.redact(many)
        let elapsed = start.duration(to: clock.now)
        let ms = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
        #expect(result.mask.count == 2)
        #expect(ms < 60, "scanning 201 snippets took \(ms) ms")
    }
}
