import Foundation

enum DockerHealthClient {
    private static let session = URLSession(configuration: .ephemeral)

    static func probe(urlString: String?, timeout: TimeInterval = 3) async -> DockerHTTPHealth {
        guard let urlString,
              let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return urlString == nil ? .none : .down
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout

        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { return .down }
            return DockerInspectParser.classifyHTTP(statusCode: response.statusCode, body: data)
        } catch {
            return .down
        }
    }
}
