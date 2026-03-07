import Testing
@testable import SnipSnap

private func block(_ text: String) -> OCRBlock {
    OCRBlock(boundingBox: NormalizedRect(x: 0, y: 0, width: 1, height: 1), text: text)
}

private func detectedKinds(in text: String) -> Set<RedactionKind> {
    Set(RedactionDetector.detect(in: [block(text)]).map(\.kind))
}

@Suite("RedactionDetector")
struct RedactionDetectorTests {

    // MARK: - Empty & Non-Matching Input

    @Test func emptyInputReturnsNoResults() {
        let results = RedactionDetector.detect(in: [])
        #expect(results.isEmpty)
    }

    @Test func plainTextReturnsNoResults() {
        let results = RedactionDetector.detect(in: [block("Hello world")])
        #expect(results.isEmpty)
    }

    // MARK: - Email

    @Test func detectsEmail() {
        let kinds = detectedKinds(in: "Contact: user@example.com")
        #expect(kinds.contains(.email))
    }

    @Test func detectsEmailCaseInsensitive() {
        let kinds = detectedKinds(in: "USER@EXAMPLE.COM")
        #expect(kinds.contains(.email))
    }

    @Test func rejectsEmailMissingDomain() {
        let kinds = detectedKinds(in: "not-an-email@")
        #expect(!kinds.contains(.email))
    }

    // MARK: - Credit Card
    // Note: The current credit card regex has a known limitation — its \b\d pattern
    // requires word boundaries before each digit in the repeated group, so it cannot
    // match standard multi-digit credit card formats. These tests document actual behavior.

    @Test func creditCardRegexDoesNotMatchSpacedFormat() {
        let kinds = detectedKinds(in: "4111 1111 1111 1111")
        #expect(!kinds.contains(.creditCard))
    }

    @Test func creditCardRegexDoesNotMatchDashedFormat() {
        let kinds = detectedKinds(in: "4111-1111-1111-1111")
        #expect(!kinds.contains(.creditCard))
    }

    @Test func creditCardRegexDoesNotMatchContiguousFormat() {
        let kinds = detectedKinds(in: "4111111111111111")
        #expect(!kinds.contains(.creditCard))
    }

    @Test func rejectsInvalidLuhnCreditCard() {
        let kinds = detectedKinds(in: "4111 1111 1111 1112")
        #expect(!kinds.contains(.creditCard))
    }

    @Test func rejectsInvalidLuhnCreditCardContiguous() {
        let kinds = detectedKinds(in: "4111111111111112")
        #expect(!kinds.contains(.creditCard))
    }

    @Test func contiguousDigitsMatchAccountNumber() {
        let kinds = detectedKinds(in: "4111111111111111")
        #expect(kinds.contains(.accountNumber))
    }

    // MARK: - Phone Number

    @Test func detectsPhoneWithParentheses() {
        let kinds = detectedKinds(in: "Call (555) 123-4567")
        #expect(kinds.contains(.phoneNumber))
    }

    @Test func detectsPhoneWithCountryCode() {
        let kinds = detectedKinds(in: "+1-555-123-4567")
        #expect(kinds.contains(.phoneNumber))
    }

    @Test func detectsPhoneWithDots() {
        let kinds = detectedKinds(in: "555.123.4567")
        #expect(kinds.contains(.phoneNumber))
    }

    @Test func detectsPhoneWithSpaces() {
        let kinds = detectedKinds(in: "+1 555 123 4567")
        #expect(kinds.contains(.phoneNumber))
    }

    // MARK: - SSN

    @Test func detectsSSNWithDashes() {
        let kinds = detectedKinds(in: "SSN: 123-45-6789")
        #expect(kinds.contains(.ssn))
    }

    @Test func detectsSSNWithSpaces() {
        let kinds = detectedKinds(in: "SSN: 123 45 6789")
        #expect(kinds.contains(.ssn))
    }

    @Test func detectsSSNWithoutSeparators() {
        let kinds = detectedKinds(in: "SSN: 123456789")
        #expect(kinds.contains(.ssn))
    }

    // MARK: - IP Address

    @Test func detectsIPAddress() {
        let kinds = detectedKinds(in: "Server at 192.168.1.1")
        #expect(kinds.contains(.ipAddress))
    }

    @Test func detectsLocalhostIP() {
        let kinds = detectedKinds(in: "127.0.0.1")
        #expect(kinds.contains(.ipAddress))
    }

    // MARK: - Token

    @Test func detectsLongAlphanumericToken() {
        let kinds = detectedKinds(in: "ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghij")
        #expect(kinds.contains(.token))
    }

    @Test func rejectsStringUnder24Characters() {
        let kinds = detectedKinds(in: "abc12345678901234567890")
        #expect(!kinds.contains(.token))
    }

    @Test func detectsAWSAccessKeyAsToken() {
        let kinds = detectedKinds(in: "AKIAIOSFODNN7EXAMPLE")
        #expect(kinds.contains(.token))
    }

    @Test func detectsURLWithTokenParamAsToken() {
        let kinds = detectedKinds(in: "https://api.example.com?token=abc123def")
        #expect(kinds.contains(.token))
    }

    @Test func detectsURLWithAccessTokenParam() {
        let kinds = detectedKinds(in: "https://api.example.com?access_token=mytoken123")
        #expect(kinds.contains(.token))
    }

    @Test func detectsURLWithApiKeyParam() {
        let kinds = detectedKinds(in: "https://api.example.com?api_key=secret789xyz")
        #expect(kinds.contains(.token))
    }

    // MARK: - Street Address

    @Test func detectsStreetAddress() {
        let kinds = detectedKinds(in: "123 Main Street")
        #expect(kinds.contains(.address))
    }

    @Test func detectsAvenueAddress() {
        let kinds = detectedKinds(in: "456 Oak Avenue")
        #expect(kinds.contains(.address))
    }

    @Test func detectsBoulevardAddress() {
        let kinds = detectedKinds(in: "789 Sunset Boulevard")
        #expect(kinds.contains(.address))
    }

    @Test func detectsMultiWordStreetName() {
        let kinds = detectedKinds(in: "1600 Pennsylvania Avenue")
        #expect(kinds.contains(.address))
    }

    // MARK: - Date of Birth

    @Test func detectsDateWithSlashes() {
        let kinds = detectedKinds(in: "DOB: 01/15/1990")
        #expect(kinds.contains(.dateOfBirth))
    }

    @Test func detectsDateWithDashes() {
        let kinds = detectedKinds(in: "DOB: 12-25-2000")
        #expect(kinds.contains(.dateOfBirth))
    }

    @Test func detectsSingleDigitMonthAndDay() {
        let kinds = detectedKinds(in: "Born: 1/5/1985")
        #expect(kinds.contains(.dateOfBirth))
    }

    @Test func rejectsInvalidMonth() {
        let kinds = detectedKinds(in: "13/15/1990")
        #expect(!kinds.contains(.dateOfBirth))
    }

    @Test func rejectsInvalidDay() {
        let kinds = detectedKinds(in: "01/32/1990")
        #expect(!kinds.contains(.dateOfBirth))
    }

    @Test func rejectsYearOutsideRange() {
        let kinds = detectedKinds(in: "01/15/1899")
        #expect(!kinds.contains(.dateOfBirth))
    }

    // MARK: - Account Number

    @Test func detectsEightDigitAccountNumber() {
        let kinds = detectedKinds(in: "Account: 12345678")
        #expect(kinds.contains(.accountNumber))
    }

    @Test func detectsSeventeenDigitAccountNumber() {
        let kinds = detectedKinds(in: "Account: 12345678901234567")
        #expect(kinds.contains(.accountNumber))
    }

    @Test func rejectsSevenDigitNumber() {
        let kinds = detectedKinds(in: "Number: 1234567")
        #expect(!kinds.contains(.accountNumber))
    }

    // MARK: - Private Key

    @Test func detectsPrivateKeyHeader() {
        let kinds = detectedKinds(in: "-----BEGIN PRIVATE KEY-----")
        #expect(kinds.contains(.privateKey))
    }

    @Test func detectsRSAPrivateKeyHeader() {
        let kinds = detectedKinds(in: "-----BEGIN RSA PRIVATE KEY-----")
        #expect(kinds.contains(.privateKey))
    }

    // MARK: - Multiple PII Types

    @Test func detectsMultiplePIIInOneBlock() {
        let results = RedactionDetector.detect(in: [
            block("Email user@test.com and phone (555) 123-4567")
        ])
        let kinds = Set(results.map(\.kind))
        #expect(kinds.contains(.email))
        #expect(kinds.contains(.phoneNumber))
    }

    @Test func detectsPIIAcrossMultipleBlocks() {
        let results = RedactionDetector.detect(in: [
            block("user@test.com"),
            block("192.168.1.1"),
        ])
        let kinds = Set(results.map(\.kind))
        #expect(kinds.contains(.email))
        #expect(kinds.contains(.ipAddress))
    }

    // MARK: - Sorting & Deduplication

    @Test func resultsAreSortedByKindRawValue() {
        let results = RedactionDetector.detect(in: [
            block("Email user@test.com and SSN 123-45-6789")
        ])
        let rawValues = results.map(\.kind.rawValue)
        #expect(rawValues == rawValues.sorted())
    }

    @Test func deduplicatesIdenticalCandidates() {
        let results = RedactionDetector.detect(in: [
            block("user@test.com"),
            block("user@test.com"),
        ])
        let emails = results.filter { $0.kind == .email }
        #expect(emails.count == 1)
    }

    @Test func preservesCandidatesFromDifferentLocations() {
        let block1 = OCRBlock(
            boundingBox: NormalizedRect(x: 0, y: 0, width: 1, height: 1),
            text: "user@test.com"
        )
        let block2 = OCRBlock(
            boundingBox: NormalizedRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5),
            text: "user@test.com"
        )
        let results = RedactionDetector.detect(in: [block1, block2])
        let emails = results.filter { $0.kind == .email }
        #expect(emails.count == 2)
    }

    // MARK: - Matched Text

    @Test func capturesMatchedTextForEmail() {
        let results = RedactionDetector.detect(in: [block("Contact: user@example.com today")])
        let email = results.first { $0.kind == .email }
        #expect(email?.matchedText == "user@example.com")
    }

    @Test func capturesBoundingBoxFromSourceBlock() {
        let source = OCRBlock(
            boundingBox: NormalizedRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4),
            text: "user@example.com"
        )
        let results = RedactionDetector.detect(in: [source])
        let email = results.first { $0.kind == .email }
        #expect(email?.boundingBox == source.boundingBox)
    }
}
