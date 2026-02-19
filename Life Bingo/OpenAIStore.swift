//
//  OpenAIStore.swift
//  Life Bingo
//
//  Created by Jason Li on 2026-02-02.
//

import Foundation

enum OpenAIStore {
    private static let envAPIKey = "OPENAI_API_KEY"
    private static let envModelKey = "OPENAI_MODEL"
    private static let storedAPIKey = "openai.apiKey"
    private static let storedModelKey = "openai.model"

    private static let storedLastUsagePrefix = "openai.lastUsage."

    static var apiKey: String {
        get {
            let stored = UserDefaults.standard.string(forKey: storedAPIKey) ?? ""
            if !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return stored.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let env = ProcessInfo.processInfo.environment[envAPIKey] ?? ""
            return env.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                UserDefaults.standard.removeObject(forKey: storedAPIKey)
            } else {
                UserDefaults.standard.set(trimmed, forKey: storedAPIKey)
            }
        }
    }

    static var model: String {
        get {
            let stored = UserDefaults.standard.string(forKey: storedModelKey) ?? ""
            let storedTrimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
            if !storedTrimmed.isEmpty {
                return storedTrimmed
            }
            let env = ProcessInfo.processInfo.environment[envModelKey] ?? ""
            let trimmed = env.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "gpt-4o-mini" : trimmed
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                UserDefaults.standard.removeObject(forKey: storedModelKey)
            } else {
                UserDefaults.standard.set(trimmed, forKey: storedModelKey)
            }
        }
    }

    static func setLastUsage(label: String, input: Int, output: Int, total: Int) {
        let key = storedLastUsagePrefix + label
        let value = "input=\(input) output=\(output) total=\(total)"
        UserDefaults.standard.set(value, forKey: key)
    }

    static func getLastUsage(label: String) -> String? {
        let key = storedLastUsagePrefix + label
        let value = UserDefaults.standard.string(forKey: key)
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

