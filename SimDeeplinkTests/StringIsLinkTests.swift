//
//  StringIsLinkTests.swift
//  SimDeeplinkTests
//

import Testing
@testable import SimDeeplink

struct StringIsLinkTests {
    @Test("Accepts web and custom-scheme deeplinks", arguments: [
        "https://example.com",
        "http://example.com/path?x=1&y=2",
        "myapp://home",
        "myapp://product/42?ref=mail#top",
        "mailto:someone@example.com",
        "my-app.v2://open"
    ])
    func acceptsDeeplink(_ text: String) {
        #expect(text.isLink)
    }

    @Test("Rejects text that is not a single URL", arguments: [
        "",
        "hello",
        "example.com",
        "myapp://",
        "https://a.com https://b.com",
        "my app://home",
        "://nothing",
        "1app://home",
        "https://example.com\n"
    ])
    func rejectsNonLink(_ text: String) {
        #expect(!text.isLink)
    }
}
