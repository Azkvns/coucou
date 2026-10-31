import Foundation
import Combine

enum DockerCatalogError: Equatable, Error {
    case emptyName
    case invalidName
    case duplicateName
    case invalidHealthURL
}

@MainActor
final class DockerCatalog: ObservableObject {
    static let storageKey = "docker.services"

    @Published private(set) var services: [DockerServiceSpec]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([DockerServiceSpec].self, from: data) {
            services = decoded
        } else {
            services = []
        }
    }

    @discardableResult
    func add(name: String, healthURL: String?) -> Result<DockerServiceSpec, DockerCatalogError> {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return .failure(.emptyName) }
        guard Self.isValidContainerName(trimmedName) else { return .failure(.invalidName) }

        let normalizedHealthURL = Self.normalizeHealthURL(healthURL)
        if case .failure(let error) = Self.validateHealthURL(normalizedHealthURL) {
            return .failure(error)
        }

        if services.contains(where: { $0.name == trimmedName }) {
            return .failure(.duplicateName)
        }

        let spec = DockerServiceSpec(id: UUID(), name: trimmedName, healthURL: normalizedHealthURL)
        services.append(spec)
        persist()
        return .success(spec)
    }

    func remove(id: UUID) {
        services.removeAll { $0.id == id }
        persist()
    }

    func update(id: UUID, name: String, healthURL: String?) -> Result<Void, DockerCatalogError> {
        guard let index = services.firstIndex(where: { $0.id == id }) else {
            return .success(())
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return .failure(.emptyName) }
        guard Self.isValidContainerName(trimmedName) else { return .failure(.invalidName) }

        let normalizedHealthURL = Self.normalizeHealthURL(healthURL)
        if case .failure(let error) = Self.validateHealthURL(normalizedHealthURL) {
            return .failure(error)
        }

        if services.contains(where: { $0.id != id && $0.name == trimmedName }) {
            return .failure(.duplicateName)
        }

        services[index].name = trimmedName
        services[index].healthURL = normalizedHealthURL
        persist()
        return .success(())
    }

    private static func normalizeHealthURL(_ healthURL: String?) -> String? {
        guard let healthURL else { return nil }
        let trimmed = healthURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func isValidContainerName(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first,
              CharacterSet.alphanumerics.contains(first),
              first.isASCII else {
            return false
        }

        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-")
        return name.unicodeScalars.allSatisfy(allowed.contains)
    }

    private static func validateHealthURL(_ healthURL: String?) -> Result<Void, DockerCatalogError> {
        guard let healthURL else { return .success(()) }
        guard let url = URL(string: healthURL),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return .failure(.invalidHealthURL)
        }
        return .success(())
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(services) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
