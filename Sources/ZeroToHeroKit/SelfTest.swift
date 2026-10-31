// `ZeroToHero --self-test [solutions.json]` checks the app's runner the way Asteria Learn checks its server: every
// lesson's solution must pass its tests and every starting point must not, compiled with this Mac's Swift. It also
// checks crashes, endless loops and compiler errors are reported. Exits 0 when everything passes.
import Foundation

enum SelfTest {
    static func run(solutionsPath: String?) async -> Int32 {
        guard let toolchain = await Toolchain.find() else {
            print("No Swift compiler found. Install Xcode or the Command Line Tools (xcode-select --install).")
            return 2
        }
        print("Swift \(toolchain.version) at \(toolchain.swiftc)")
        let course: Course
        do { course = try Course.load() } catch { print("Could not load the course: \(error)"); return 2 }
        let path = solutionsPath ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "../../Resources/solutions.json").standardized.path
        guard let data = FileManager.default.contents(atPath: path),
              let solutions = try? JSONDecoder().decode([String: String].self, from: data) else {
            print("Could not read \(path)"); return 2
        }

        var failures: [String] = []
        let lesson = course.lesson("values-constants")!
        let crash = await Runner.check(lesson, code: "let language = \"Swift\"\nlet a: [Int] = []\nprint(a[1])", toolchain: toolchain)
        if !(crash.crashed && crash.crashReason.contains("Index out of range")) { failures.append("a crash was not reported") }
        let loop = await Runner.check(lesson, code: "let language = \"Swift\"\nwhile true {}", toolchain: toolchain, runTimeout: 2)
        if !loop.timedOut { failures.append("an endless loop was not stopped") }
        let bad = await Runner.check(lesson, code: "let language = \"Swift\"\nlet n: Int = \"no\"", toolchain: toolchain)
        if bad.compiled || bad.errors.first?.line != 2 { failures.append("a compiler error was not reported on line 2") }

        let coded = course.lessons.filter(\.hasCode)
        if coded.count != solutions.count { failures.append("\(coded.count) lessons with code, but \(solutions.count) solutions") }
        // a few at a time: each compile uses a core
        var checked = 0
        await withTaskGroup(of: [String].self) { group in
            var queue = coded[...]
            func next() {
                guard let l = queue.popFirst() else { return }
                group.addTask {
                    var problems: [String] = []
                    guard let solution = solutions[l.id] else { return ["\(l.id): no solution"] }
                    let good = await Runner.check(l, code: solution, toolchain: toolchain)
                    if !good.passed {
                        problems.append("\(l.id): the solution fails \(good.errors.map(\.message)) \(good.tests.filter { !$0.passed }.map(\.text))")
                    }
                    if let seed = l.seed, seed != solution, await Runner.check(l, code: seed, toolchain: toolchain).passed {
                        problems.append("\(l.id): the starting code already passes")
                    }
                    return problems
                }
            }
            for _ in 0..<max(2, ProcessInfo.processInfo.activeProcessorCount - 1) { next() }
            for await problems in group {
                failures += problems
                checked += 1
                if checked % 10 == 0 { print("\(checked) of \(coded.count) lessons checked") }
                next()
            }
        }

        if failures.isEmpty {
            print("All \(coded.count) lessons with code check out, and the runner reports crashes, loops and errors.")
            return 0
        }
        print("\(failures.count) problem(s):")
        failures.forEach { print("  " + $0) }
        return 1
    }
}
