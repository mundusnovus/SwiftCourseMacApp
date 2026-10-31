// Runs exercises on Asteria Learn's server, for iPhone and iPad, which cannot compile Swift themselves. The server
// builds the code with the lesson's tests the same way the Mac's LocalRunner does (MNLearn/src/runner.mjs) and sends
// back the result. No account: the request carries a random id for this install, which the server uses only to limit
// how many runs an hour one install can make, and the server keeps nothing.
import Foundation

nonisolated struct RemoteRunner: CodeRunner {
    static let endpoint = URL(string: "https://learn.asteria.technology/api/app/run")!

    let device: String
    var session: URLSession = .shared

    /// This install's random id, made once and kept in UserDefaults.
    static var installID: String {
        let key = "installID"
        if let id = UserDefaults.standard.string(forKey: key), UUID(uuidString: id) != nil { return id }
        let id = UUID().uuidString.lowercased()
        UserDefaults.standard.set(id, forKey: key)
        return id
    }

    struct Problem: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private struct Reply: Decodable {
        struct Test: Decodable { let text: String; let pass: Bool }
        struct Failure: Decodable { let line: Int?; let message: String }
        var compiled: Bool?
        var timedOut: Bool?
        var crashed: Bool?
        var crash: String?
        var output: String?
        var errors: [Failure]?
        var tests: [Test]?
        var error: String?
    }

    func check(_ lesson: Lesson, code: String) async throws -> RunResult {
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 90)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(device, forHTTPHeaderField: "x-asteria-device")
        request.httpBody = try JSONEncoder().encode(["id": lesson.id, "code": code])
        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw Problem(message: "Asteria Learn can't be reached. Your code runs there, so check your internet connection and try again.")
        }
        let reply = try? JSONDecoder().decode(Reply.self, from: data)
        guard (response as? HTTPURLResponse)?.statusCode == 200, let reply else {
            throw Problem(message: reply?.error ?? "Your code couldn't be run just now. Try again in a moment.")
        }
        var result = RunResult()
        result.compiled = reply.compiled ?? false
        result.errors = (reply.errors ?? []).map { RunResult.CompilerError(line: $0.line, message: $0.message) }
        result.output = reply.output ?? ""
        result.crashed = reply.crashed ?? false
        result.crashReason = reply.crash ?? ""
        result.timedOut = reply.timedOut ?? false
        result.tests = (reply.tests ?? []).map { RunResult.TestResult(text: $0.text, passed: $0.pass) }
        return result
    }
}
