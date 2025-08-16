import XCTest
@testable import podcasts

class ShowNotesChapterExtractorTests: XCTestCase {

    // MARK: - Real Show Notes Examples

    func testHTMLStructuredChapters() {
        // Real example from podcast with HTML structured chapters
        let showNotes = """
        <p><em><strong>Well, it looks like Tech IPO's might be back on the menu because Figma's first day pop was like the good old days. Anthropic seems to be getting traction, OpenAI raises again. Earnings from Apple and Amazon, and of course, the Weekend Longreads Suggestions.</strong></em></p>
        <p><strong>Chapters:</strong></p>
        <p><strong>00:33 Figma IPO</strong></p>
        <p><strong>04:57  Anthropic And Open AI Numbers</strong></p>
        <p><strong>08:45 New Deep Think Model</strong></p>
        <p><strong>11:08 Tech Earnings</strong></p>
        <p><strong>15:30 Weekend Longreads</strong></p>
        <p>Rest of the shownotes go here...</p>
        """

        let chapters = ShowNotesChapterExtractor.extractChaptersFromShowNotes(showNotes)

        XCTAssertEqual(chapters.count, 5)

        XCTAssertEqual(chapters[0].title, "Figma IPO")
        XCTAssertEqual(chapters[0].startTime, 33.0)

        XCTAssertEqual(chapters[1].title, "Anthropic And Open AI Numbers")
        XCTAssertEqual(chapters[1].startTime, 297.0)

        XCTAssertEqual(chapters[2].title, "New Deep Think Model")
        XCTAssertEqual(chapters[2].startTime, 525.0)

        XCTAssertEqual(chapters[3].title, "Tech Earnings")
        XCTAssertEqual(chapters[3].startTime, 668.0)

        XCTAssertEqual(chapters[4].title, "Weekend Longreads")
        XCTAssertEqual(chapters[4].startTime, 930.0)
    }

    func testParenthesesFormatWithMixedTimestamps() {
        // Real example from Bret Taylor podcast with both MM:SS and HH:MM:SS formats
        let showNotes = """
        <p><strong>In this episode, we cover:</strong></p>
        <p>(00:00) Introduction to Bret Taylor</p>
        <p>(04:10) Bret's early career and first major mistake</p>
        <p>(08:24) The birth of Google Maps</p>
        <p>(11:57) Lessons from FriendFeed and the importance of honest feedback</p>
        <p>(31:30) The future of coding and AI's role</p>
        <p>(45:26) Preparing the next generation for an AI-driven world</p>
        <p>(48:46) AI in education</p>
        <p>(52:05) Business strategies in the AI market</p>
        <p>(01:04:38) Outcome-based pricing in AI</p>
        <p>(01:09:15) Productivity gains and AI</p>
        <p>(01:17:35) Go-to-market strategies for AI products</p>
        <p>(01:21:49) Lightning round and final thoughts</p>
        """

        let chapters = ShowNotesChapterExtractor.extractChaptersFromShowNotes(showNotes)

        XCTAssertEqual(chapters.count, 12)

        // Test MM:SS format
        XCTAssertEqual(chapters[0].title, "Introduction to Bret Taylor")
        XCTAssertEqual(chapters[0].startTime, 0.0)

        XCTAssertEqual(chapters[1].title, "Bret's early career and first major mistake")
        XCTAssertEqual(chapters[1].startTime, 250.0)

        XCTAssertEqual(chapters[7].title, "Business strategies in the AI market")
        XCTAssertEqual(chapters[7].startTime, 3125.0)

        // Test HH:MM:SS format
        XCTAssertEqual(chapters[8].title, "Outcome-based pricing in AI")
        XCTAssertEqual(chapters[8].startTime, 3878.0) // 01:04:38 = 3878 seconds

        XCTAssertEqual(chapters[9].title, "Productivity gains and AI")
        XCTAssertEqual(chapters[9].startTime, 4155.0) // 01:09:15 = 4155 seconds

        XCTAssertEqual(chapters[11].title, "Lightning round and final thoughts")
        XCTAssertEqual(chapters[11].startTime, 4909.0) // 01:21:49 = 4909 seconds
    }

    // MARK: - Edge Cases and Format Variations

    func testBracketFormatTimestamps() {
        let showNotes = """
        In this episode:
        [00:15] Introduction to the show
        [02:30] Main discussion begins
        [15:00] Deep dive section
        [1:05:30] Final thoughts
        """

        let chapters = ShowNotesChapterExtractor.extractChaptersFromShowNotes(showNotes)

        XCTAssertEqual(chapters.count, 4)
        XCTAssertEqual(chapters[0].title, "Introduction to the show")
        XCTAssertEqual(chapters[0].startTime, 15.0)
        XCTAssertEqual(chapters[3].title, "Final thoughts")
        XCTAssertEqual(chapters[3].startTime, 3930.0)
    }

    func testDashSeparatedTimestamps() {
        let showNotes = """
        00:15 - Introduction
        02:30 - Main topic discussion
        15:45 - Q&A session
        """

        let chapters = ShowNotesChapterExtractor.extractChaptersFromShowNotes(showNotes)

        XCTAssertEqual(chapters.count, 3)
        XCTAssertEqual(chapters[0].title, "Introduction")
        XCTAssertEqual(chapters[0].startTime, 15.0)
        XCTAssertEqual(chapters[1].title, "Main topic discussion")
        XCTAssertEqual(chapters[1].startTime, 150.0)
        XCTAssertEqual(chapters[2].title, "Q&A session")
        XCTAssertEqual(chapters[2].startTime, 945.0)
    }

    func testTimestampsWithHTMLEntities() {
        let showNotes = """
        <p><strong>00:15</strong> - Introduction &amp; Overview</p>
        <p><strong>02:30</strong> &nbsp; Main Topic &mdash; Deep Dive</p>
        <p><strong>15:45</strong> Q&amp;A Section</p>
        """

        let chapters = ShowNotesChapterExtractor.extractChaptersFromShowNotes(showNotes)

        print("DEBUG: Found \(chapters.count) chapters")
        for (i, chapter) in chapters.enumerated() {
            print("DEBUG: Chapter \(i): '\(chapter.title)' at \(chapter.startTime)")
        }

        XCTAssertEqual(chapters.count, 3)
        if chapters.count >= 1 { XCTAssertEqual(chapters[0].title, "Introduction & Overview") }
        if chapters.count >= 2 { XCTAssertEqual(chapters[1].title, "Main Topic — Deep Dive") }
        if chapters.count >= 3 { XCTAssertEqual(chapters[2].title, "Q&A Section") }
    }

    func testDuplicateTimestamps() {
        let showNotes = """
        <p>(00:15) Introduction</p>
        <p>(00:15) Still introduction (duplicate)</p>
        <p>(02:30) Main topic</p>
        """

        let chapters = ShowNotesChapterExtractor.extractChaptersFromShowNotes(showNotes)

        // Should only include the first occurrence of each timestamp
        XCTAssertEqual(chapters.count, 2)
        XCTAssertEqual(chapters[0].title, "Introduction")
        XCTAssertEqual(chapters[0].startTime, 15.0)
        XCTAssertEqual(chapters[1].title, "Main topic")
        XCTAssertEqual(chapters[1].startTime, 150.0)
    }

    func testChronologicalOrdering() {
        let showNotes = """
        <p>(15:45) Third chapter</p>
        <p>(00:15) First chapter</p>
        <p>(02:30) Second chapter</p>
        """

        let chapters = ShowNotesChapterExtractor.extractChaptersFromShowNotes(showNotes)

        XCTAssertEqual(chapters.count, 3)
        // Should be sorted by time
        XCTAssertEqual(chapters[0].title, "First chapter")
        XCTAssertEqual(chapters[0].startTime, 15.0)
        XCTAssertEqual(chapters[1].title, "Second chapter")
        XCTAssertEqual(chapters[1].startTime, 150.0)
        XCTAssertEqual(chapters[2].title, "Third chapter")
        XCTAssertEqual(chapters[2].startTime, 945.0)
    }

    func testEmptyShowNotes() {
        let showNotes = ""
        let chapters = ShowNotesChapterExtractor.extractChaptersFromShowNotes(showNotes)
        XCTAssertEqual(chapters.count, 0)
    }

    func testShowNotesWithoutTimestamps() {
        let showNotes = """
        This is a regular podcast episode description.
        It talks about various topics but doesn't include any timestamps.
        No chapters should be extracted from this content.
        """

        let chapters = ShowNotesChapterExtractor.extractChaptersFromShowNotes(showNotes)
        XCTAssertEqual(chapters.count, 0)
    }

    func testMixedFormatsInSameShowNotes() {
        let showNotes = """
        <p><strong>Chapters:</strong></p>
        <p><strong>00:33 HTML Strong Format</strong></p>
        <p>(04:10) Parentheses Format</p>
        <p>08:24 - Dash Format</p>
        <p>[11:57] Bracket Format</p>
        """

        let chapters = ShowNotesChapterExtractor.extractChaptersFromShowNotes(showNotes)

        // Should extract from the first working pattern (HTML strong format in this case)
        XCTAssertGreaterThan(chapters.count, 0)
        XCTAssertEqual(chapters[0].title, "HTML Strong Format")
        XCTAssertEqual(chapters[0].startTime, 33.0)
    }
}
