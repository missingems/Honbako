@testable import Sumi
import AidokuRunner
import Testing

struct HonbakoEarlierChapterPolicyTests {
    private func chapter(_ key: String, number: Float?, language: String? = "en") -> AidokuRunner.Chapter {
        var value = AidokuRunner.Chapter(key: key, chapterNumber: number)
        value.language = language
        return value
    }

    @Test("Earlier unread chapters follow the selected translation's source order, including specials and volume resets")
    func translationAndSourceOrder() {
        let newest = chapter("v2-1", number: 1)
        let selected = chapter("selected", number: 30)
        let special = chapter("special", number: nil)
        let old = chapter("old", number: 28)
        let translated = chapter("es-old", number: 28, language: "es")
        let result = HonbakoEarlierChapterPolicy.unreadBefore(selected,
            in: [newest, selected, translated, special, old], completedKeys: ["old"])
        #expect(result.map(\.key) == ["special"])
        #expect(HonbakoEarlierChapterPolicy.unreadBefore(newest,
            in: [newest, selected, special, old], completedKeys: []).map(\.key) == ["old", "special", "selected"])
    }

    @Test("A missing selected chapter never marks unrelated chapters; completed entries and duplicate keys stay excluded")
    func missingAndDuplicates() {
        let selected = chapter("selected", number: 3)
        let one = chapter("one", number: 1)
        #expect(HonbakoEarlierChapterPolicy.unreadBefore(selected, in: [one], completedKeys: []).isEmpty)
        #expect(HonbakoEarlierChapterPolicy.unreadBefore(selected,
            in: [selected, one, one], completedKeys: []).map(\.key) == ["one"])
        #expect(HonbakoEarlierChapterPolicy.unreadBefore(selected,
            in: [selected, one], completedKeys: ["one"]).isEmpty)
    }
}
