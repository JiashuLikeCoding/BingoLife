import Foundation
import SwiftUI

private struct AppLanguageKey: EnvironmentKey {
    static let defaultValue: AppLanguage = .zhTW
}

extension EnvironmentValues {
    var appLanguage: AppLanguage {
        get { self[AppLanguageKey.self] }
        set { self[AppLanguageKey.self] = newValue }
    }
}

enum L10n {
    private static let en: [String: String] = [
        "我很棒": "I'm Great",
        "感恩": "Gratitude",
        "Bingo": "Bingo",
        "記錄": "Habits",
        "獎勵": "Rewards",
        "設定": "Settings",
        "習慣": "Habits",
        "今日狀態": "Daily Check-in",
        "歡迎": "Welcome",
        "開始之前": "Before We Start",
        "開始": "Start",
        "保存": "Save",
        "取消": "Cancel",
        "添加": "Add",
        "添加目標": "Add Goal",
        "添加習慣": "Add Habit",
        "添加小目標": "Add Subgoal",
        "管理目標": "Manage Goals",
        "換一換": "Refresh",
        "你的目標": "Your Goals",
        "你的習慣": "Your Habits",
        "ChatGPT 設定": "ChatGPT",
        "ChatGPT API Key": "ChatGPT API Key",
        "輸入 API Key": "Enter API Key",
        "顯示金鑰": "Show Key",
        "隱藏金鑰": "Hide Key",
        "模型（預設 gpt-4o-mini）": "Model (default gpt-4o-mini)",
        "外觀與語言": "Appearance & Language",
        "語言": "Language",
        "配色": "Theme",
        "提示": "Notice",
        "知道了": "OK",
        "想要獎勵自己什麼": "What would you like to reward yourself?",
        "想獎勵自己什麼": "Your reward idea",
        "所需 coin": "Coins needed",
        "獎勵自己": "Add Reward",
        "可兌換": "Available",
        "已兌換": "Redeemed",
        "還沒有獎勵": "No rewards yet",
        "新增一個你想兌換的獎勵。": "Add a reward you'd like to redeem.",
        "還沒有兌換紀錄": "No redemptions yet",
        "完成第一個兌換目標吧。": "Complete your first reward goal.",
        "兌換": "Redeem",
        "coin 不足": "Not enough coins",
        "兌換成功": "Redeemed successfully",
        "我能做到": "I Can Do It",
        "保持節奏，讓心慢慢穩定。": "Keep a gentle rhythm."
    ]

    static func t(_ key: String, _ language: AppLanguage) -> String {
        switch language {
        case .zhTW:
            return key
        case .en:
            return en[key] ?? key
        }
    }
}

enum LanguageStore {
    private static let key = "app.language"

    static var code: String? {
        get {
            UserDefaults.standard.string(forKey: key)
        }
        set {
            let trimmed = (newValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                UserDefaults.standard.removeObject(forKey: key)
            } else {
                UserDefaults.standard.set(trimmed, forKey: key)
            }
        }
    }
}
