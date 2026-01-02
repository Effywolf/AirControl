//
//  ProfileManager.swift
//  CameraTest
//

import Foundation

// MARK: - ProfileError

enum ProfileError: Error, LocalizedError {
    case cannotDeleteDefault
    case profileNotFound
    case invalidThresholds
    case storageError(String)

    var errorDescription: String? {
        switch self {
        case .cannotDeleteDefault:
            return "Cannot delete the default profile"
        case .profileNotFound:
            return "Profile not found"
        case .invalidThresholds:
            return "Profile contains invalid threshold values"
        case .storageError(let message):
            return "Storage error: \(message)"
        }
    }
}

// MARK: - ProfileManager

class ProfileManager {
    // MARK: - Properties

    private let storageURL: URL
    private var profiles: [GestureProfile] = []
    private var activeProfileId: UUID?

    private let profilesFileName = "profiles.json"
    private let activeProfileKey = "activeProfileId"

    // Serial queue for thread-safe access
    private let queue = DispatchQueue(label: "com.cameratest.profilemanager", qos: .userInitiated)

    // MARK: - Initialization

    init() {
        // Setup storage location: ~/Library/Application Support/CameraTest/Profiles/
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        storageURL = appSupport
            .appendingPathComponent("CameraTest")
            .appendingPathComponent("Profiles")

        // Create directory if needed
        try? FileManager.default.createDirectory(
            at: storageURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        // Load profiles from disk
        profiles = loadProfiles()

        // Ensure default profile exists
        if !profiles.contains(where: { $0.isDefault }) {
            profiles.append(.defaultProfile)
            saveProfiles()
        }

        // Load active profile ID
        activeProfileId = loadActiveProfileId()

        // If no active profile or it doesn't exist, use default
        if activeProfileId == nil || !profiles.contains(where: { $0.id == activeProfileId }) {
            activeProfileId = defaultProfile.id
            saveActiveProfileId(activeProfileId!)
        }
    }

    // MARK: - CRUD Operations

    /// Creates a new profile with the given name and thresholds
    @discardableResult
    func createProfile(name: String, thresholds: GestureThresholds) throws -> GestureProfile {
        // Validate thresholds
        guard thresholds.validate() else {
            throw ProfileError.invalidThresholds
        }

        // Handle duplicate names
        var uniqueName = name
        var counter = 2
        while profiles.contains(where: { $0.name == uniqueName }) {
            uniqueName = "\(name) (\(counter))"
            counter += 1
        }

        let profile = GestureProfile(
            name: uniqueName,
            thresholds: thresholds,
            isDefault: false
        )

        profiles.append(profile)
        saveProfiles()
        return profile
    }

    /// Updates an existing profile
    func updateProfile(_ profile: GestureProfile) throws {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else {
            throw ProfileError.profileNotFound
        }

        guard profile.thresholds.validate() else {
            throw ProfileError.invalidThresholds
        }

        var updated = profile
        updated.touch()
        profiles[index] = updated
        saveProfiles()
    }

    /// Deletes a profile by ID
    func deleteProfile(id: UUID) throws {
        guard let profile = profiles.first(where: { $0.id == id }) else {
            throw ProfileError.profileNotFound
        }

        guard !profile.isDefault else {
            throw ProfileError.cannotDeleteDefault
        }

        profiles.removeAll { $0.id == id }

        // If we deleted the active profile, switch to default
        if activeProfileId == id {
            activeProfileId = defaultProfile.id
            saveActiveProfileId(activeProfileId!)
        }

        saveProfiles()
    }

    /// Returns all profiles sorted by name
    func getAllProfiles() -> [GestureProfile] {
        return profiles.sorted { profile1, profile2 in
            // Default profile always comes first
            if profile1.isDefault { return true }
            if profile2.isDefault { return false }
            return profile1.name.localizedCaseInsensitiveCompare(profile2.name) == .orderedAscending
        }
    }

    /// Gets a profile by ID
    func getProfile(id: UUID) -> GestureProfile? {
        return profiles.first { $0.id == id }
    }

    // MARK: - Active Profile Management

    /// Sets the active profile
    func setActiveProfile(id: UUID) throws {
        guard profiles.contains(where: { $0.id == id }) else {
            throw ProfileError.profileNotFound
        }

        activeProfileId = id
        saveActiveProfileId(id)
    }

    /// Gets the currently active profile
    func getActiveProfile() -> GestureProfile {
        if let id = activeProfileId,
           let profile = profiles.first(where: { $0.id == id }) {
            return profile
        }
        return defaultProfile
    }

    /// Gets the default profile
    var defaultProfile: GestureProfile {
        if let profile = profiles.first(where: { $0.isDefault }) {
            return profile
        }

        // Should never happen due to init, but fallback just in case
        let profile = GestureProfile.defaultProfile
        profiles.append(profile)
        saveProfiles()
        return profile
    }

    // MARK: - Persistence

    private func loadProfiles() -> [GestureProfile] {
        let fileURL = storageURL.appendingPathComponent(profilesFileName)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return [GestureProfile.defaultProfile]
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let profiles = try decoder.decode([GestureProfile].self, from: data)
            return profiles
        } catch {
            print("Failed to load profiles: \(error)")
            return [GestureProfile.defaultProfile]
        }
    }

    private func saveProfiles() {
        let fileURL = storageURL.appendingPathComponent(profilesFileName)
        let profilesToSave = profiles // Capture current state

        queue.async {
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(profilesToSave)
                try data.write(to: fileURL, options: .atomic)
            } catch {
                print("Failed to save profiles: \(error)")
            }
        }
    }

    private func loadActiveProfileId() -> UUID? {
        guard let uuidString = UserDefaults.standard.string(forKey: activeProfileKey) else {
            return nil
        }
        return UUID(uuidString: uuidString)
    }

    private func saveActiveProfileId(_ id: UUID) {
        UserDefaults.standard.set(id.uuidString, forKey: activeProfileKey)
    }

    // MARK: - Utility Methods

    /// Resets a profile to default thresholds (keeps name and metadata)
    func resetProfileToDefaults(id: UUID) throws {
        guard var profile = profiles.first(where: { $0.id == id }) else {
            throw ProfileError.profileNotFound
        }

        profile.thresholds = .defaults
        try updateProfile(profile)
    }

    /// Exports a profile to JSON data
    func exportProfile(id: UUID) throws -> Data {
        guard let profile = profiles.first(where: { $0.id == id }) else {
            throw ProfileError.profileNotFound
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(profile)
    }

    /// Imports a profile from JSON data
    @discardableResult
    func importProfile(from data: Data) throws -> GestureProfile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var profile = try decoder.decode(GestureProfile.self, from: data)

        // Ensure imported profile isn't marked as default
        profile.isDefault = false

        // Validate thresholds
        guard profile.thresholds.validate() else {
            throw ProfileError.invalidThresholds
        }

        // Create new ID and handle name conflicts
        return try createProfile(name: profile.name, thresholds: profile.thresholds)
    }
}
