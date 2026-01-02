//
//  GestureProfile.swift
//  CameraTest
//
//  Created by Claude on 2026-01-01.
//

import Foundation

struct GestureProfile: Codable, Identifiable, Equatable {
    // MARK: - Properties

    /// Unique identifier for the profile
    let id: UUID

    /// User-friendly name for the profile
    var name: String

    /// Date when the profile was created
    var createdDate: Date

    /// Date when the profile was last modified
    var lastModified: Date

    /// Gesture recognition thresholds for this profile
    var thresholds: GestureThresholds

    /// Whether this is the system default profile (cannot be deleted)
    var isDefault: Bool

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        name: String,
        createdDate: Date = Date(),
        lastModified: Date = Date(),
        thresholds: GestureThresholds,
        isDefault: Bool = false
    ) {
        self.id = id
        self.name = name
        self.createdDate = createdDate
        self.lastModified = lastModified
        self.thresholds = thresholds
        self.isDefault = isDefault
    }

    // MARK: - Factory Methods

    /// Creates the default system profile with factory threshold settings
    static var defaultProfile: GestureProfile {
        return GestureProfile(
            name: "Default",
            thresholds: .defaults,
            isDefault: true
        )
    }

    // MARK: - Mutations

    /// Updates the last modified date to the current time
    mutating func touch() {
        lastModified = Date()
    }
}

// MARK: - CustomStringConvertible

extension GestureProfile: CustomStringConvertible {
    var description: String {
        let defaultIndicator = isDefault ? " (Default)" : ""
        return "\(name)\(defaultIndicator) - Modified: \(lastModified.formatted())"
    }
}
