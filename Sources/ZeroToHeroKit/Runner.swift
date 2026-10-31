// Runs a learner's code against a lesson's tests with the Swift compiler on this Mac, the same way Asteria Learn's
// server does (MundusNovusLearn/src/runner.mjs): the code and the tests become one main.swift, the learner's code
// first, then each test in its own block with an expect() of its own, reporting through a marker line with a random
// nonce. Output and source checks are regular expressions, checked here.
import Foundation

nonisolated struct RunResult: Sendable {
    struct TestResult: Sendable {
        let text: String
        let passed: Bool
    }
    struct CompilerError: Sendable, Hashable {
        let line: Int?        // in the learner's code, from 1; nil when the problem is in the tests
        let message: String
    }

    var compiled = true
    var errors: [CompilerError] = []
    var output = ""
    var crashed = false
    var crashReason = ""
    var timedOut = false
    var tests: [TestResult] = []

    var passed: Bool { compiled && !timedOut && !tests.isEmpty && tests.allSatisfy(\.passed) }
}

#if os(macOS)
/// Runs exercises with the Swift compiler on this Mac.
nonisolated struct LocalRunner: CodeRunner {
    let toolchain: Toolchain
    func check(_ lesson: Lesson, code: String) async throws -> RunResult {
        await Runner.check(lesson, code: code, toolchain: toolchain)
    }
}

/// Where the Swift compiler is, and which version, or why it cannot be used.
nonisolated struct Toolchain: Sendable {
    let swiftc: String
    let sdk: String           // the macOS SDK, found once: looking it up on every compile races when several run at once
    let version: String       // like "6.4"

    var isRecentEnough: Bool { version.compare("6.2", options: .numeric) != .orderedAscending }
    var hasEverything: Bool { version.compare("6.4", options: .numeric) != .orderedAscending }

    /// nil when no developer tools are installed. Looking does not trigger Apple's install prompt.
    @concurrent
    static func find() async -> Toolchain? {
        guard (try? await Shell.run("/usr/bin/xcode-select", ["-p"], timeout: 10))?.status == 0,
              let found = try? await Shell.run("/usr/bin/xcrun", ["--find", "swiftc"], timeout: 20), found.status == 0 else { return nil }
        let swiftc = found.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let sdkPath = try? await Shell.run("/usr/bin/xcrun", ["--sdk", "macosx", "--show-sdk-path"], timeout: 20), sdkPath.status == 0,
              let v = try? await Shell.run(swiftc, ["--version"], timeout: 20) else { return nil }
        let sdk = sdkPath.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = v.stdout + v.stderr
        let version = text.firstMatch(of: /Swift version (\d+\.\d+)/).map { String($0.1) } ?? "?"
        return Toolchain(swiftc: swiftc, sdk: sdk, version: version)
    }
}

nonisolated enum Runner {
    static let prelude = """
    #if canImport(Darwin)
    import Darwin
    setvbuf(stdout, nil, _IOLBF, 0)
    #endif

    """
    static var preludeLines: Int { prelude.components(separatedBy: "\n").count - 1 }

    /// The program the compiler sees, and the line where the tests start (to tell errors in the tests apart).
    static func program(code: String, tests: [LessonTest], nonce: String) -> (source: String, firstLine: Int, testStart: Int) {
        var blocks: [String] = []
        for (i, test) in tests.enumerated() {
            for check in test.checks where check.kind == .swift {
                let body = check.code.split(separator: "\n", omittingEmptySubsequences: false).map { "    " + $0 }.joined(separator: "\n")
                blocks.append("""
                do {
                    var __mnPass = true
                    func expect(_ condition: @autoclosure () throws -> Bool) { do { if try !condition() { __mnPass = false } } catch { __mnPass = false } }
                \(body)
                    print("\\u{1E}\(nonce) \(i) \\(__mnPass ? 1 : 0)")
                }
                """)
            }
        }
        let learner = code.replacingOccurrences(of: "\r", with: "")
        let testStart = preludeLines + learner.components(separatedBy: "\n").count + 2
        let source = prelude + learner + "\n\n// MARK: the lesson's tests\n" + blocks.joined(separator: "\n") + "\n"
        return (source, preludeLines + 1, testStart)
    }

    /// Compiles and runs `code` with `lesson`'s tests.
    @concurrent
    static func check(_ lesson: Lesson, code: String, toolchain: Toolchain, runTimeout: Double = 8) async -> RunResult {
        var result = RunResult()
        var passed = Array(repeating: true, count: lesson.tests.count)
        var swiftLeft = lesson.tests.map { $0.checks.filter { $0.kind == .swift }.count }

        for (i, test) in lesson.tests.enumerated() {
            for check in test.checks {
                if check.kind == .source, !matches(check.code, in: code) { passed[i] = false }
                if check.kind == .nosource, matches(check.code, in: code) { passed[i] = false }
            }
        }

        let nonce = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let built = program(code: code, tests: lesson.tests, nonce: nonce)
        let dir = FileManager.default.temporaryDirectory.appending(path: "zero-to-hero-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try built.source.write(to: dir.appending(path: "main.swift"), atomically: true, encoding: .utf8)
        } catch {
            result.compiled = false
            result.errors = [.init(line: nil, message: "Could not write a temporary file: \(error.localizedDescription)")]
            result.tests = lesson.tests.map { .init(text: $0.text, passed: false) }
            return result
        }

        // Swift 6 with the settings Xcode gives new app projects: the main actor by default
        let flags = ["-sdk", toolchain.sdk, "-swift-version", "6", "-default-isolation", "MainActor", "-enable-upcoming-feature", "NonisolatedNonsendingByDefault",
                     "-Onone", "-module-name", "Lesson", "-o", "program", "main.swift"]
        let compile = try? await Shell.run(toolchain.swiftc, flags, in: dir, timeout: 60)
        let program = dir.appending(path: "program")
        guard let compile, compile.status == 0, FileManager.default.fileExists(atPath: program.path) else {
            result.compiled = false
            result.timedOut = compile?.timedOut ?? false
            result.errors = compilerErrors(compile?.stderr ?? "The compiler could not be started.", firstLine: built.firstLine, testStart: built.testStart)
            for (i, test) in lesson.tests.enumerated() where swiftLeft[i] > 0 || test.checks.contains(where: { $0.kind == .output || $0.kind == .nooutput }) {
                passed[i] = false
            }
            result.tests = zip(lesson.tests, passed).map { .init(text: $0.text, passed: $1) }
            return result
        }

        let run = try? await Shell.run(program.path, [], in: dir, timeout: runTimeout)
        var shown: [Substring] = []
        for line in (run?.stdout ?? "").split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("\u{1E}\(nonce) ") {
                let parts = line.split(separator: " ")
                if parts.count == 3, let i = Int(parts[1]), i < passed.count {
                    swiftLeft[i] -= 1
                    if parts[2] != "1" { passed[i] = false }
                }
            } else {
                shown.append(line)
            }
        }
        result.output = shown.joined(separator: "\n").trimmingCharacters(in: .newlines)
        result.timedOut = run?.timedOut ?? false
        result.crashed = !result.timedOut && (run?.status ?? 1) != 0
        if result.crashed { result.crashReason = crashReason(run?.stderr ?? "") }

        for (i, test) in lesson.tests.enumerated() {
            if swiftLeft[i] > 0 { passed[i] = false }
            for check in test.checks {
                if check.kind == .output, !matches(check.code, in: result.output) { passed[i] = false }
                if check.kind == .nooutput, matches(check.code, in: result.output) { passed[i] = false }
            }
        }
        result.tests = zip(lesson.tests, passed).map { .init(text: $0.text, passed: $1) }
        return result
    }

    /// Regular expressions are written for JavaScript on the website; the common subset works the same here.
    nonisolated static func matches(_ pattern: String, in text: String) -> Bool {
        guard let rx = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return false }
        return rx.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    nonisolated static func compilerErrors(_ stderr: String, firstLine: Int, testStart: Int) -> [RunResult.CompilerError] {
        var out: [RunResult.CompilerError] = []
        for line in stderr.split(separator: "\n") {
            guard let m = line.firstMatch(of: /main\.swift:(\d+):(\d+): error: (.*)/), let n = Int(m.1) else { continue }
            out.append(n >= testStart ? .init(line: nil, message: "The tests could not use your code: " + m.3)
                                      : .init(line: n - firstLine + 1, message: String(m.3)))
        }
        if out.isEmpty, !stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            out.append(.init(line: nil, message: stderr.split(separator: "\n").suffix(3).joined(separator: " ")))
        }
        return Array(out.prefix(12))
    }

    nonisolated static func crashReason(_ stderr: String) -> String {
        if let m = stderr.firstMatch(of: /Fatal error: ([^\n]*)/) { return String(m.1) }
        return "Your program stopped unexpectedly."
    }
}

/// Runs a command and collects its output, stopping it after a timeout.
nonisolated enum Shell {
    struct Output: Sendable {
        var status: Int32
        var stdout: String
        var stderr: String
        var timedOut: Bool
    }

    private final class Box: @unchecked Sendable {
        let lock = NSLock()
        var out = Data(), err = Data(), resumed = false
    }

    nonisolated static func run(_ executable: String, _ arguments: [String], in directory: URL? = nil, timeout: Double) async throws -> Output {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let directory { process.currentDirectoryURL = directory }
        // A clean environment: settings from whatever launched the app (like SDKROOT when built from Terminal) must not
        // leak into the learner's compile
        var env: [String: String] = [:]
        for key in ["PATH", "HOME", "USER", "LANG", "TMPDIR", "DEVELOPER_DIR"] { env[key] = ProcessInfo.processInfo.environment[key] }
        env["PATH"] = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = env
        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        let box = Box(), limit = 256 * 1024
        outPipe.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            box.lock.withLock { if box.out.count < limit { box.out.append(d) } }
        }
        errPipe.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            box.lock.withLock { if box.err.count < limit { box.err.append(d) } }
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Output, Error>) in
            let timedOut = Box()
            process.terminationHandler = { p in
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                let restOut = outPipe.fileHandleForReading.readDataToEndOfFile()
                let restErr = errPipe.fileHandleForReading.readDataToEndOfFile()
                let output: Output = box.lock.withLock {
                    box.out.append(restOut); box.err.append(restErr)
                    return Output(status: p.terminationStatus, stdout: String(decoding: box.out, as: UTF8.self),
                                  stderr: String(decoding: box.err, as: UTF8.self), timedOut: timedOut.lock.withLock { timedOut.resumed })
                }
                continuation.resume(returning: output)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
                return
            }
            let pid = process.processIdentifier
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                guard process.isRunning else { return }
                timedOut.lock.withLock { timedOut.resumed = true }
                kill(pid, SIGKILL)
            }
        }
    }
}
#endif
