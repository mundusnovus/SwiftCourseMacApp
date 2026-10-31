// The course, as exported from Asteria Learn (MundusNovusLearn/tools/export-app.mjs) into Resources/course.json.
import Foundation

nonisolated struct Course: Decodable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let versions: String
    let summary: String
    let chapters: [Chapter]

    var lessons: [Lesson] { chapters.flatMap { $0.modules.flatMap(\.lessons) } }

    func lesson(_ id: Lesson.ID) -> Lesson? { lessons.first { $0.id == id } }

    func module(of id: Lesson.ID) -> (chapter: Chapter, module: Module)? {
        for chapter in chapters {
            for module in chapter.modules where module.lessons.contains(where: { $0.id == id }) {
                return (chapter, module)
            }
        }
        return nil
    }

    func neighbours(of id: Lesson.ID) -> (previous: Lesson?, next: Lesson?) {
        let all = lessons
        guard let i = all.firstIndex(where: { $0.id == id }) else { return (nil, nil) }
        return (i > 0 ? all[i - 1] : nil, i + 1 < all.count ? all[i + 1] : nil)
    }
}

nonisolated struct Chapter: Decodable, Sendable, Identifiable {
    let title: String
    let summary: String
    let modules: [Module]
    var id: String { title }
}

nonisolated struct Module: Decodable, Sendable, Identifiable {
    let id: String
    let title: String
    let lessons: [Lesson]
}

nonisolated struct Lesson: Decodable, Sendable, Identifiable, Hashable {
    enum Kind: String, Decodable, Sendable {
        case lesson, workshop, lab, quiz, xcode, project

        var label: String {
            switch self {
            case .lesson: "Lesson"
            case .workshop: "Workshop"
            case .lab: "Lab"
            case .quiz: "Quiz"
            case .xcode: "Xcode"
            case .project: "Project"
            }
        }
    }

    let id: String
    let title: String
    let type: Kind
    let minutes: Int
    let description: [Block]
    let instructions: [Block]
    let seed: String?
    let tests: [LessonTest]
    let hints: [String]
    let checklist: [String]
    let questions: [Question]

    var hasCode: Bool { !tests.isEmpty }

    static func == (a: Lesson, b: Lesson) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// A test is a sentence with one or more checks; it passes when every check does.
nonisolated struct LessonTest: Decodable, Sendable {
    let text: String
    let checks: [Check]
}

nonisolated struct Check: Decodable, Sendable {
    enum Kind: String, Decodable, Sendable {
        case swift              // Swift code run after the learner's, calling expect(...)
        case output, nooutput   // a regular expression the printed output must (or must not) match
        case source, nosource   // a regular expression the code must (or must not) match
    }
    let kind: Kind
    let code: String
}

nonisolated struct Question: Decodable, Sendable {
    struct Answer: Decodable, Sendable {
        let text: String
        let correct: Bool
    }
    let question: String
    let detail: [Block]
    let answers: [Answer]
    let why: String
}

/// Lesson text, block by block. Inline text is Markdown: bold, italics, `code` and links.
nonisolated indirect enum Block: Decodable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case code(language: String, code: String)
    case list(ordered: Bool, items: [String])
    case note(kind: String, blocks: [Block])
    case quote([Block])
    case table(head: [String], rows: [[String]])
    case rule

    private enum Keys: String, CodingKey { case type, level, text, lang, code, ordered, items, kind, blocks, head, rows }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "heading": self = .heading(level: try c.decode(Int.self, forKey: .level), text: try c.decode(String.self, forKey: .text))
        case "code": self = .code(language: try c.decode(String.self, forKey: .lang), code: try c.decode(String.self, forKey: .code))
        case "list": self = .list(ordered: try c.decode(Bool.self, forKey: .ordered), items: try c.decode([String].self, forKey: .items))
        case "note": self = .note(kind: try c.decode(String.self, forKey: .kind), blocks: try c.decode([Block].self, forKey: .blocks))
        case "quote": self = .quote(try c.decode([Block].self, forKey: .blocks))
        case "table": self = .table(head: try c.decode([String].self, forKey: .head), rows: try c.decode([[String]].self, forKey: .rows))
        case "rule": self = .rule
        default: self = .paragraph(try c.decodeIfPresent(String.self, forKey: .text) ?? "")
        }
    }
}

extension Course {
    enum LoadError: Error { case missing }

    /// The course shipped inside the app (or the repository's Resources when running from the package).
    static func load() throws -> Course {
        guard let url = Resources.url("course.json") else { throw LoadError.missing }
        return try JSONDecoder().decode(Course.self, from: Data(contentsOf: url))
    }
}
