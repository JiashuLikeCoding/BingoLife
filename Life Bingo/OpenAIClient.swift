//
//  OpenAIClient.swift
//  Life Bingo
//
//  Created by Jason Li on 2026-02-02.
//

import Foundation

struct OpenAIClient {
    let apiKey: String
    let model: String

    func generateTasks(
        habit: String,
        motivation: String,
        size: Int,
        completionRate: Double,
        completedLines: Int,
        completedFullBoards: Int
    ) async throws -> [String] {
        let difficulty: String
        switch completionRate {
        case ..<0.4:
            difficulty = "簡單"
        case 0.4..<0.7:
            difficulty = "中等"
        default:
            difficulty = "進階"
        }

        let prompt = """
        你是習慣養成教練，請用繁體中文生成 Bingo 任務。
        請輸出 JSON，格式如下：
        { "tasks": ["任務1", "任務2", ...] }
        規則：
        - 需要 \(size * size) 條任務，長度 6-20 字
        - 任務要具體，可執行，正向
        - 任務不可包含「每天」「每日」「天天」等字樣
        - 符合使用者習慣：\(habit)
        - 動機：\(motivation)
        - 難度：\(difficulty)
        - 目前已完成 Bingo 線數：\(completedLines)
        - 累積完成整張：\(completedFullBoards)
        - 任務不可重複
        請只回傳 JSON。
        """

        let requestBody: [String: Any] = [
            "model": model,
            "input": [
                [
                    "role": "system",
                    "content": "You are a helpful assistant. Respond in JSON only."
                ],
                [
                    "role": "user",
                    "content": prompt
                ]
            ],
            "text": [
                "format": [
                    "type": "json_object"
                ]
            ],
            "max_output_tokens": 700
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: [])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIError.network("無法取得回應")
        }
        if !(200...299).contains(http.statusCode) {
            let message = String(data: data, encoding: .utf8) ?? "狀態碼 \(http.statusCode)"
            throw OpenAIError.server(message)
        }

        let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        if let error = decoded.error {
            throw OpenAIError.server(error.message)
        }

        let text = decoded.outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw OpenAIError.parse("回應內容為空")
        }

        guard let jsonData = text.data(using: .utf8) else {
            throw OpenAIError.parse("JSON 解析失敗")
        }
        let taskResponse = try JSONDecoder().decode(TaskResponse.self, from: jsonData)
        return taskResponse.tasks
    }

    func generateTaskPool(
        goals: [String],
        priorityGoals: [String],
        tasksPerGoal: Int,
        extraCount: Int,
        blockedTopics: [String],
        difficultyMode: DifficultyMode,
        goalSubgoals: [String: [String]],
        checkin: DailyCheckin?,
        isInitialBoard: Bool
    ) async throws -> TaskPoolResponse {
        let goalList = goals.isEmpty ? "（無）" : goals.map { "- \($0)" }.joined(separator: "\n")
        let priorityList = priorityGoals.isEmpty ? "（無）" : priorityGoals.map { "- \($0)" }.joined(separator: "\n")
        let blockedList = blockedTopics.isEmpty ? "（無）" : blockedTopics.map { "- \($0)" }.joined(separator: "\n")
        let subgoalList: String = {
            guard !goalSubgoals.isEmpty else { return "（無）" }
            return goalSubgoals
                .filter { !$0.value.isEmpty }
                .map { key, value in
                    let items = value.map { "- \($0)" }.joined(separator: "\n")
                    return "\(key):\n\(items)"
                }
                .joined(separator: "\n")
        }()
        let checkinText: String
        if let checkin {
            checkinText = "mood_score: \(checkin.moodScore), motivation_score: \(checkin.motivationScore), difficulty_score: \(checkin.difficultyScore)"
        } else {
            checkinText = "（今日尚未填寫）"
        }
        let modeRule: String
        switch difficultyMode {
        case .initial:
            modeRule = "模式：初始。任務必須極度容易（1-10 分鐘內），不需出門、不需花錢、不需社交、不需長時間專注、不需準備或收尾。"
        case .protect:
            modeRule = "模式：保護。任務僅限放鬆、自我照顧、情緒穩定、降低刺激；不需出門、不需社交；避免推進型語意。"
        case .easeUp:
            modeRule = "模式：降低。整體難度下降 10-20%，優先降低時間與專注深度。"
        case .keep:
            modeRule = "模式：維持。難度不變，只更新表達與新鮮感。"
        case .gentleUp:
            modeRule = "模式：小幅提升。僅上調一個維度 +15-20%（例如時間稍長或更接觸），不可同時增加多維度。"
        case .slightUp:
            modeRule = "模式：微升。僅上調一個維度 +10%（例如時間稍長或更接觸），不可同時增加多維度。"
        case .microUp:
            modeRule = "模式：超微升。只能新增一個很輕的維度，或僅 +10%（二擇一），不可同時增加多維度。"
        }
        let stageHint: String
        if isInitialBoard || difficultyMode == .protect {
            stageHint = "Stage 0-1（心理/低摩擦接觸）"
        } else if difficultyMode == .easeUp {
            stageHint = "回到 Stage 0-1"
        } else if difficultyMode == .keep {
            stageHint = "Stage 2（極短實作）"
        } else {
            stageHint = "Stage 1-2（低摩擦接觸 → 極短實作）"
        }
        let prompt = """
        你是溫和的任務設計師，目標是保護使用者動機與情緒。
        所有大型習慣必須視為長期行為路徑（Stage 0-4），不可跳級；只能給出當前 Stage 的最低阻力步驟。
        請輸出 JSON，格式如下：
        {
          "goalTasks": {
            "目標1": ["任務1","任務2","任務3"],
            "目標2": ["任務1","任務2","任務3"]
          },
          "extraTasks": ["任務A", "任務B", ...]
        }
        規則：
        - 每個目標產生 \(tasksPerGoal) 條任務
        - 另外產生 \(extraCount) 條任務（可為自我照顧、感受當下、情緒穩定類）
        - 任務長度 6-20 字，具體、可執行、溫和
        - 每條任務必須在 30 分鐘內完成（若為初始模式，請限制在 1-10 分鐘）
        - 任務不可包含「每天」「每日」「天天」等字樣
        - 任務不可重複
        - 任務主題需與「好好生活、感受當下、感受自然、減少焦慮、提升靈魂、感受活著」相關
        - 若有優先目標，所有任務中至少 50% 要與優先目標相關（可隱含但需明確相關）
        - 避免引發內疚、自責或比較的語氣
        - 難度只能依據 difficulty_score 判斷，禁止自行推測
        - \(modeRule)
        - 不要生成與以下主題相關的任務：
        \(blockedList)
        - 目標清單如下（請使用完全相同的目標文字作為 key）：
        \(goalList)
        - 小目標清單如下（若有，請優先使用小目標來生成任務，並與目標結合）：
        \(subgoalList)
        - 若某目標有小目標，該目標的任務請優先從小目標產生（不足再用大目標）
        - 優先目標如下：
        \(priorityList)
        - 今日狀態（僅供判斷）：
        \(checkinText)
        - 若 mood_score ≥ 50 且 motivation_score ≥ 50，目標相關任務比例約 70%，非目標約 30%
        - 當前 Stage 建議：
        \(stageHint)
        - 是否為首次生成：\(isInitialBoard ? "是" : "否")
        只回傳 JSON。
        """

        let requestBody: [String: Any] = [
            "model": model,
            "input": [
                [
                    "role": "system",
                    "content": "You are a helpful assistant. Respond in JSON only."
                ],
                [
                    "role": "user",
                    "content": prompt
                ]
            ],
            "text": [
                "format": [
                    "type": "json_object"
                ]
            ],
            "max_output_tokens": 1200
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: [])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIError.network("無法取得回應")
        }
        if !(200...299).contains(http.statusCode) {
            let message = String(data: data, encoding: .utf8) ?? "狀態碼 \(http.statusCode)"
            throw OpenAIError.server(message)
        }

        let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        if let error = decoded.error {
            throw OpenAIError.server(error.message)
        }

        let text = decoded.outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw OpenAIError.parse("回應內容為空")
        }

        guard let jsonData = text.data(using: .utf8) else {
            throw OpenAIError.parse("JSON 解析失敗")
        }
        return try JSONDecoder().decode(TaskPoolResponse.self, from: jsonData)
    }

    func estimateCoinCost(for text: String) async throws -> Int {
        let prompt = """
        請根據以下目標估算需要的 coin 數量（1-50 之間的整數）。
        規則：內容越耗時、越難堅持，coin 越高。
        只回傳 JSON，格式：
        { "coins": 12 }
        目標：\(text)
        """

        let requestBody: [String: Any] = [
            "model": model,
            "input": [
                [
                    "role": "system",
                    "content": "You are a helpful assistant. Respond in JSON only."
                ],
                [
                    "role": "user",
                    "content": prompt
                ]
            ],
            "text": [
                "format": [
                    "type": "json_object"
                ]
            ],
            "max_output_tokens": 120
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: [])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIError.network("無法取得回應")
        }
        if !(200...299).contains(http.statusCode) {
            let message = String(data: data, encoding: .utf8) ?? "狀態碼 \(http.statusCode)"
            throw OpenAIError.server(message)
        }

        let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        if let error = decoded.error {
            throw OpenAIError.server(error.message)
        }

        let text = decoded.outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw OpenAIError.parse("回應內容為空")
        }

        guard let jsonData = text.data(using: .utf8) else {
            throw OpenAIError.parse("JSON 解析失敗")
        }
        let coinResponse = try JSONDecoder().decode(CoinEstimateResponse.self, from: jsonData)
        return coinResponse.coins
    }

    func generateGoodDeedFeedback(note: String, duration: TimeInterval?, source: GoodDeedSource) async throws -> String {
        let durationText: String
        if let duration {
            let total = Int(duration)
            let hours = total / 3600
            let minutes = (total % 3600) / 60
            let seconds = total % 60
            durationText = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            durationText = "無"
        }
        let prompt = """
        你是溫和的自我肯定教練。請用繁體中文給出一句短回饋，肯定使用者剛剛完成的正向行為與專注時間。
        回饋需包含：
        - 肯定行為本身
        - 若提供專注時長，請溫和提及；若為「無」，不要提及時間
        禁止：
        - KPI、評分、排名、比較
        - 說教或命令語氣
        請輸出 JSON：
        { "message": "..." }
        使用者行為：\(note)
        專注時長：\(durationText)
        來源：\(source.rawValue)
        """

        let requestBody: [String: Any] = [
            "model": model,
            "input": [
                [
                    "role": "system",
                    "content": "You are a helpful assistant. Respond in JSON only."
                ],
                [
                    "role": "user",
                    "content": prompt
                ]
            ],
            "text": [
                "format": [
                    "type": "json_object"
                ]
            ],
            "max_output_tokens": 200
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: [])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIError.network("無法取得回應")
        }
        if !(200...299).contains(http.statusCode) {
            let message = String(data: data, encoding: .utf8) ?? "狀態碼 \(http.statusCode)"
            throw OpenAIError.server(message)
        }

        let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        if let error = decoded.error {
            throw OpenAIError.server(error.message)
        }

        let text = decoded.outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw OpenAIError.parse("回應內容為空")
        }

        guard let jsonData = text.data(using: .utf8) else {
            throw OpenAIError.parse("JSON 解析失敗")
        }

        struct FeedbackResponse: Decodable {
            let message: String
        }

        let responseObj = try JSONDecoder().decode(FeedbackResponse.self, from: jsonData)
        return responseObj.message
    }

    private func generateHabitResearchReport(goal: String, previousError: String? = nil) async throws -> HabitResearchReport {
        let sanitizedGoal = goal
            .replacingOccurrences(of: "每天", with: "")
            .replacingOccurrences(of: "每日", with: "")
            .replacingOccurrences(of: "天天", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let previousErrorBlock: String = {
            guard let previousError, !previousError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
            return "\n【上次輸出未通過驗證】\n\(previousError)\n請你修正後重新輸出，並確保完全符合本次的數量與格式要求。\n"
        }()

        let prompt = """
        你是行為科學導向的習慣養成研究員與產品設計師。
        請先為「\(sanitizedGoal.isEmpty ? goal : sanitizedGoal)」寫一份研究報告（PASS 1），用繁體中文，並輸出 JSON。
        \(previousErrorBlock)

        【硬規則】
        - 使用者輸入可能包含「每天/每日/天天」，但你在任何輸出欄位都不得重複這些字樣。
        - 你要做的是「心理工程／行為設計」，不是把時間切細遞增。
        - 內容要具體，可落地；禁止用口號充數。

        【輸出格式（只能輸出這個 JSON；不要額外文字）】
        {
          "summary": ["..."],
          "userArchetypeHypotheses": ["..."],
          "frictionMechanisms": ["..."],
          "failureModes": ["..."],
          "interventionPlan": [
            {
              "interventionId": "I1",
              "title": "...",
              "mechanism": "...",
              "howItReducesResistance": "...",
              "variants": ["...", "..."],
              "recoveryScript": ["...", "..."],
              "successSignals": ["...", "..."]
            }
          ]
        }

        【內容要求（務必照「陣列元素數量」來寫；不可把多行合併成同一個字串）】
        - summary：這不是簡短摘要，而是「28 天內有效養成」的完整設計回答（PASS 1 的總藍圖）。
          - 必須是陣列，元素數量 8–12 個。
          - 每個元素 20–60 字左右，內容要像一段完整說明（可包含：設計原則/對應阻力/替代方案/中斷回復/可觀察成功徵兆）。
          - 每個元素必須以固定標籤之一開頭（擇一）：
            - 「總策略：」
            - 「第1週：」
            - 「第2週：」
            - 「第3週：」
            - 「第4週：」
            - 「替代方案：」
            - 「中斷後回復：」
            - 「成功徵兆：」
          - 不要寫成『第 N 天要做到 X 分鐘』這種 KPI/遞增計畫；要寫行為設計與抗中斷策略。
        - frictionMechanisms：至少 4 點，每點要帶具體例子（例如：下班決策疲勞→坐低就唔想郁）。
        - failureModes：至少 3 點，寫成具體情境。
        - interventionPlan：至少 4 條干預策略。
          - 每條必須同「frictionMechanisms / failureModes」對應。
          - variants：至少 2 個（太累/落雨/時間少/情緒差等低配版本）。
          - recoveryScript：至少 2 個（錯過一次之後點樣回到最小版本；唔追 KPI、唔補做）。
          - successSignals：至少 2 個可觀察徵兆（唔係 KPI）。

        只回傳 JSON。
        """

        let requestBody: [String: Any] = [
            "model": model,
            "input": [
                ["role": "system", "content": "You are a helpful assistant. Respond in JSON only."],
                ["role": "user", "content": prompt]
            ],
            "text": ["format": ["type": "json_object"]],
            "max_output_tokens": 1800
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: [])
        request.timeoutInterval = 120

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIError.network("無法取得回應")
        }
        if !(200...299).contains(http.statusCode) {
            let message = String(data: data, encoding: .utf8) ?? "狀態碼 \(http.statusCode)"
            throw OpenAIError.server(message)
        }

        let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        if let error = decoded.error {
            throw OpenAIError.server(error.message)
        }

        let text = decoded.outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let jsonData = text.data(using: .utf8) else {
            throw OpenAIError.parse("回應內容為空")
        }

        var report: HabitResearchReport
        do {
            report = try JSONDecoder().decode(HabitResearchReport.self, from: jsonData)
        } catch {
            let preview = text.prefix(400)
            throw OpenAIError.parse("研究報告 JSON 解析失敗：\(error.localizedDescription)\npreview: \(preview)")
        }

        // Basic validation to ensure PASS 1 is not empty / not template.
        // Some models may accidentally put multi-line content into a single array element.
        // We salvage by splitting the first element into lines, but only if that yields enough non-empty items.
        if report.summary.count < 8, report.summary.count == 1 {
            let merged = report.summary[0]
            let lines = merged
                .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if lines.count >= 8 {
                report.summary = Array(lines.prefix(12))
            }
        }

        if report.summary.count < 8 { throw OpenAIError.parse("研究報告 summary 太短（需要 8–12 段）") }
        if report.frictionMechanisms.count < 4 { throw OpenAIError.parse("研究報告 frictionMechanisms 少於 4") }
        if report.failureModes.count < 3 { throw OpenAIError.parse("研究報告 failureModes 少於 3") }
        if report.interventionPlan.count < 4 { throw OpenAIError.parse("研究報告 interventionPlan 少於 4") }

        // summary must include key blueprint components (so it's a real answer, not a vague preface)
        let summaryText = report.summary.joined(separator: "\n")
        let requiredSummaryKeywords = ["替代方案", "中斷後回復", "成功徵兆"]
        for k in requiredSummaryKeywords {
            if !summaryText.contains(k) {
                throw OpenAIError.parse("研究報告 summary 必須包含關鍵段落：\(k)")
            }
        }

        for itv in report.interventionPlan {
            if itv.interventionId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw OpenAIError.parse("研究報告 interventionId 不可為空")
            }
            if itv.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw OpenAIError.parse("研究報告 intervention title 不可為空")
            }
            if itv.variants.filter({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }).count < 2 {
                throw OpenAIError.parse("研究報告 \(itv.interventionId) variants 少於 2")
            }
            if itv.recoveryScript.filter({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }).count < 2 {
                throw OpenAIError.parse("研究報告 \(itv.interventionId) recoveryScript 少於 2")
            }
        }

        return report
    }

    func generateHabitGuide(goal: String) async throws -> HabitGuide {
        let researchReport: HabitResearchReport
        do {
            researchReport = try await generateHabitResearchReport(goal: goal)
        } catch {
            // One self-fix retry: feed the validation error back to PASS 1.
            let errText: String
            if let e = error as? OpenAIError {
                errText = String(describing: e)
            } else {
                errText = error.localizedDescription
            }
            researchReport = try await generateHabitResearchReport(goal: goal, previousError: errText)
        }

        // Avoid echoing user-entered cadence words that are banned in AI output.
        // We keep the original goal for UI display elsewhere, but prompt the model with a neutral phrasing.
        let sanitizedGoal = goal
            .replacingOccurrences(of: "每天", with: "")
            .replacingOccurrences(of: "每日", with: "")
            .replacingOccurrences(of: "天天", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        func extractTargetMinutes(from text: String) -> Int? {
            let patterns = ["(\\d{1,3})\\s*分鐘", "(\\d{1,3})\\s*分", "(\\d{1,3})\\s*minutes", "(\\d{1,3})\\s*mins", "(\\d{1,3})\\s*min"]
            for p in patterns {
                if let regex = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]) {
                    let range = NSRange(text.startIndex..<text.endIndex, in: text)
                    if let match = regex.firstMatch(in: text, options: [], range: range), match.numberOfRanges >= 2,
                       let r1 = Range(match.range(at: 1), in: text) {
                        return Int(text[r1])
                    }
                }
            }
            return nil
        }
        let targetMinutes = extractTargetMinutes(from: goal)
        let targetMinutesRule: String = {
            guard let targetMinutes, targetMinutes >= 10 else { return "" }
            return "\n【重要：目標時長硬性要求】\n- 目標包含 \(targetMinutes) 分鐘：stage 4（扎根）必須至少有 1 個核心行為 step，並且該 step 的 duration 欄位必須明確寫「\(targetMinutes) 分鐘」（阿拉伯數字），不要用『半小時』這類模糊寫法。\n"
        }()

        let interventionCatalog: String = {
            let items = researchReport.interventionPlan.map { itv in
                let title = itv.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let mech = itv.mechanism.trimmingCharacters(in: .whitespacesAndNewlines)
                let reduce = itv.howItReducesResistance.trimmingCharacters(in: .whitespacesAndNewlines)
                return "- \(itv.interventionId): \(title)｜機制：\(mech)｜降低阻力：\(reduce)"
            }
            return items.joined(separator: "\n")
        }()

        let prompt = """
        你是習慣地圖設計師。請為「\(sanitizedGoal.isEmpty ? goal : sanitizedGoal)」生成一份 5 階段的 Habit Map（PASS 2）。
        注意：使用者輸入的目標可能包含「每天/每日/天天」等字樣，但你在任何輸出欄位都不得重複這些字樣；請用不含頻率詞的描述來寫所有步驟與任務。

        【PASS 1 研究報告（interventionPlan）】
        你只能使用以下干預策略來設計 steps / bingoTasks；不准憑空新增新的策略或口號。
        \(interventionCatalog)

        【第一：熟練定義（必須具體可觀察）】
        禁止：抽象描述如「自然地做」「成為生活一部份」「養成習慣」「持續執行」。
        必須：描述「做得到時，外在會出現什麼具體行為/徵兆」。
        範例（好）：
        - 「能夠在想到要做時，直接去做，不再需要『心理準備』」
        - 「偶爾忘記/中斷後，能在 24 小時內自己回來，不需要別人提醒」
        - 「做這件事時，心裡對自己沒有苛責聲音」

        【第二：阻力分析（必須具體）】
        禁止：「時間不夠」「懶」「不自律」這種標籤式描述。
        必須：具體描述「什麼情境/什麼東西/什麼想法」阻礙行動。
        範例（好）：
        - 「想到要換運動服，就覺得麻煩」（阻力：怕麻煩的感覺）
        - 「坐在沙發上後，就不想動」（阻力：舒適區的吸引力）
        - 「打開運動影片，看不懂要怎麼做」（阻力：不知道第一步）

        【第三：五階段與步驟（最重要）】
        必須包含 5 個 STAGE（stage=0..4）。每個 STAGE 的 steps 數量可以彈性（建議 3–8 步），但每個 stage 至少要有 1 步。

        【Stage 劃分定義（必須照做，並在輸出中反映）】
        - stage 0 種子：只做「接觸/準備/環境布置」，幾乎零阻力。
          例：把物品放到視線內、設定提醒、把工具準備好。
        - stage 1 發芽：一段「超短實作」（至少 30 秒），讓行為第一次做得出。
          例：做 30–90 秒的動作、走到門口並站 30 秒。
        - stage 2 長葉：可重複的「短流程」（仍然低阻力），減少每次決策。
          例：固定 3–8 分鐘流程（熱身→做→收尾）。
        - stage 3 開花：在不同情境仍做得到（忙、累、天氣差、被打斷），要有替代版本。
          例：下雨版/加班版/出差版的替代步。
        - stage 4 扎根：中斷後能回到軌道（自我修復），並且更少需要提醒。
          例：錯過一次後的「回歸步驟」+ 環境已固定。
        \(targetMinutesRule)

        **STEP 的規則（每一步都是一個具體行動）：**
        禁止：
        - 「培養觸發點」「建立儀式」「克服阻力」—— 這些是目標，不是行動
        - 「Day 1: ...」格式，直接寫行動
        - 必須是「做 XXX」「選定 XXX」「把 XXX 放好」「打開 XXX」
        範例（好）：
        - 「選定明日運動時間」
        - 「把運動服放在床邊」
        - 「下載並打開運動 App」
        - 「穿好運動襪」
        - 「做 3 下深蹲」

        **BINGO TASKS 的規則（比 step 更細的動作）：**
        每個 step 產生 bingoTasks（數量彈性，但至少 1 個；必須直接可執行）。

        【重要：不同 stage 的 bingoTasks 尺度規則】
        - stage 0（種子）：bingoTasks 可以很細（例如「打開/點擊/設定」類），因為重點是降低阻力。
        - stage 1–4（發芽/長葉/開花/扎根）：
          - 每個 bingoTask 必須是「至少 30 秒」的一段動作
          - 必須包含「身體動作/實際行為」（例如：走、拿、穿、做、整理、把某物放到某處、實際完成一小段流程）
          - 盡量避免只用「打開/點擊/設定」當作任務（除非目標本身就是數位/整理類）

        禁止：「換心態」「給自己鼓勵」「深呼吸」——除非目標本身是情緒相關。

        範例：
        - stage 0（種子）可以：
          - 「打開手機日曆」
          - 「選定明天一個具體時間」
          - 「設定提醒」
        - stage 1（發芽）更應該：
          - 「穿上運動鞋並走到門口」
          - 「原地踏步 60 秒」
          - 「做 5 次深蹲」

        【嚴格禁止（再次強調）】
        - 「做一個很小的步驟」「開始行動」「嘗試一下」—— 廢話
        - 「閉眼呼吸」「對自己說肯定句」—— 無關任務
        - 任何包含「每天」「每日」「天天」的句子

        【輸出 JSON 格式】
        {
          "masteryDefinition": "具體可觀察的熟練狀態（不要 KPI）",
          "frictions": ["具體阻力1", "具體阻力2", "具體阻力3"],
          "methodRoute": [
            "漸進策略：用 3–6 句描述從最小版本 → 目標行為的漸進路線（可操作行為）",
            "替代方案：列出太累/雨天/時間少時的低配版本（可操作行為）",
            "中斷後回復：錯過一次後，下一次如何回到最小版本（可操作行為；不追 KPI）"
          ],
          "stages": [
            {
              "stage": 0,
              "stageName": "種子",
              "steps": [
                {
                  "stepId": "S1",
                  "derivedFromInterventionIds": ["I1"],
                  "title": "具體行動（做 XXX / 選定 XXX / 把 XXX 放好）",
                  "duration": "30 秒",
                  "fallback": "更小版本",
                  "category": "行為/環境/心理",
                  "requiredBingoCount": 2,
                  "bingoTasks": ["細動作1", "細動作2", "細動作3"]
                }
              ]
            }
          ]
        }

        【第一：研究分析（必須先做，然後才寫 steps）】
        你要先想清楚「用戶為何做不到」以及「點樣先會養成」，並把分析落地成可執行策略：
        - frictions：至少 3 點，且每點要具體（要有情境/原因，例如「下班太累」「換衫麻煩」「落雨冇地方」），禁止只寫「沒時間/沒動力」呢種泛句。
        - methodRoute：至少 3 點（可多）；每點必須是「可操作行為」。**為了避免漏項，請用固定標籤格式**，並且至少各出現一次：
          - 「漸進策略：...」
          - 「替代方案：...」（太累/雨天/時間少時的低配版本）
          - 「中斷後回復：...」（錯過後如何回到最小版本；不追 KPI）
          - 「觸發情境：...」可寫可不寫（建議但不必填）

        【硬性輸出驗證（你必須滿足）】
        - methodRoute 至少 3 點（越完整越好），且每點是可操作行為（禁止抽象口號）。為避免漏寫，methodRoute 內必須至少各有一點以以下字首開頭：
          - 漸進策略：
          - 替代方案：
          - 中斷後回復：
          （觸發情境：可選）
        - stages 必須剛好 5 個（stage=0..4），每個 stage 至少 1 個 steps（可彈性）。
        - 每個 step 必須有 stepId，且 stepId 必須跟 stage 對應：
          - stage 0: S1..Sn
          - stage 1: P1..Pn
          - stage 2: L1..Ln
          - stage 3: B1..Bn
          - stage 4: R1..Rn
        - 【PASS2 追溯要求】每個 step 必須包含 derivedFromInterventionIds（陣列，至少 1 個），而且只能使用 PASS 1 的 interventionId（例如 I1/I2...）。
        - 每個 step 必須包含 requiredBingoCount（1–3，代表完成幾個 Bingo 任務先算完成該 step）。
        - 每個 step 的 bingoTasks 至少 1 個，且全都是細動作（可直接做，不需要用戶再決定做咩）。

        只回傳 JSON，不要有任何其他文字。
        """

        let requestBody: [String: Any] = [
            "model": model,
            "input": [
                [
                    "role": "system",
                    "content": "You are a helpful assistant. Respond in JSON only."
                ],
                [
                    "role": "user",
                    "content": prompt
                ]
            ],
            "text": [
                "format": [
                    "type": "json_object"
                ]
            ],
            "max_output_tokens": 3500
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: [])
        request.timeoutInterval = 120

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            // Common on iOS when app backgrounds / network switches mid-request.
            if let urlError = error as? URLError,
               urlError.code == .networkConnectionLost || urlError.code == .timedOut {
                // One quick retry.
                try? await Task.sleep(nanoseconds: 600_000_000) // 0.6s
                (data, response) = try await URLSession.shared.data(for: request)
            } else {
                throw error
            }
        }
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIError.network("無法取得回應")
        }
        if !(200...299).contains(http.statusCode) {
            let message = String(data: data, encoding: .utf8) ?? "狀態碼 \(http.statusCode)"
            throw OpenAIError.server(message)
        }

        // Extract output text robustly from multiple possible OpenAI response shapes.
        var text: String
        do {
            // 1) Preferred: decode using our typed shape.
            let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
            if let error = decoded.error {
                throw OpenAIError.server(error.message)
            }
            text = decoded.outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            // 2) Fallback: parse as generic JSON (responses/chat.completions variants).
            let raw = String(data: data, encoding: .utf8) ?? ""

            // If API returned an error payload, surface it.
            if let obj = try? JSONSerialization.jsonObject(with: data, options: []),
               let dict = obj as? [String: Any],
               let err = dict["error"] as? [String: Any],
               let msg = err["message"] as? String {
                throw OpenAIError.server(msg)
            }

            // Try to extract output_text from Responses API: { output: [ { content: [ { type, text } ] } ] }
            if let obj = try? JSONSerialization.jsonObject(with: data, options: []),
               let dict = obj as? [String: Any] {
                if let outputText = dict["output_text"] as? String {
                    text = outputText.trimmingCharacters(in: .whitespacesAndNewlines)
                } else if let output = dict["output"] as? [[String: Any]] {
                    var chunks: [String] = []
                    for item in output {
                        if let content = item["content"] as? [[String: Any]] {
                            for c in content {
                                let type = (c["type"] as? String) ?? ""
                                if type == "output_text" || type == "text" {
                                    if let t = c["text"] as? String { chunks.append(t) }
                                }
                            }
                        }
                    }
                    text = chunks.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                } else if let choices = dict["choices"] as? [[String: Any]] {
                    // Chat Completions style
                    let first = choices.first
                    if let message = first?["message"] as? [String: Any],
                       let content = message["content"] as? String {
                        text = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    } else if let delta = first?["delta"] as? [String: Any],
                              let content = delta["content"] as? String {
                        text = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    } else {
                        text = ""
                    }
                } else {
                    text = ""
                }
            } else {
                text = ""
            }

            if text.isEmpty {
                // Last resort: try to grab the first JSON object in raw text.
                if let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}"), start < end {
                    text = String(raw[start...end]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }

            if text.isEmpty {
                let preview = raw.prefix(400)
                print("OpenAI raw response (preview): \(preview)")
                throw OpenAIError.parse("cannot parse response (preview): \(preview)")
            }
        }

        guard !text.isEmpty, let jsonData = text.data(using: .utf8) else {
            throw OpenAIError.parse("回應內容為空")
        }
        
        // Try to decode, if fails, throw to trigger fallback
        let responseModel: HabitGuideResponse
        do {
            responseModel = try JSONDecoder().decode(HabitGuideResponse.self, from: jsonData)
        } catch {
            // Log the raw response for debugging
            let preview = text.prefix(400)
            print("AI HabitGuide JSON parsing failed: \(error)")
            print("Raw response (preview): \(preview)")
            throw OpenAIError.parse("JSON 解析失敗：\(error.localizedDescription)\npreview: \(preview)")
        }

        let masteryDefinition = (responseModel.masteryDefinition ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let frictions = (responseModel.frictions ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let methodRoute = (responseModel.methodRoute ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Strict validation: no local fallback templates.
        try Self.validateHabitGuideResponse(goal: goal, researchReport: researchReport, masteryDefinition: masteryDefinition, frictions: frictions, methodRoute: methodRoute, response: responseModel)

        let stages = responseModel.stages
            .sorted { $0.stage < $1.stage }
            .map { stage -> HabitStageGuide in
                let steps = stage.steps.map { step -> HabitGuideStep in
                    let trimmedStepId = (step.stepId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedTitle = step.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedFallback = step.fallback.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedDuration = step.duration.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedCategory = (step.category ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

                    let tasks = (step.bingoTasks?.tasks ?? [])
                        .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }

                    let required = max(1, min(3, step.requiredBingoCount ?? 1))
                    let bingoTaskObjs: [BingoTask] = {
                        if let field = step.bingoTasks {
                            return field.tasks.enumerated().map { idx, t in
                                let taskId = (t.taskId ?? "\(trimmedStepId)-T\(idx + 1)").trimmingCharacters(in: .whitespacesAndNewlines)
                                let mapsTo = (t.mapsToStep ?? trimmedStepId).trimmingCharacters(in: .whitespacesAndNewlines)
                                let derived = (t.derivedFromInterventionIds ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                                let text = t.text.trimmingCharacters(in: .whitespacesAndNewlines)
                                let durationSec = max(1, t.durationSec ?? 45)
                                let observable = (t.observable ?? "完成：\(text)").trimmingCharacters(in: .whitespacesAndNewlines)
                                let sp = min(0.99, max(0.01, t.successProbability ?? 0.75))
                                return BingoTask(taskId: taskId, mapsToStep: mapsTo, derivedFromInterventionIds: derived, text: text, durationSec: durationSec, observable: observable, successProbability: sp)
                            }
                        }
                        // Should not happen due to validation, but keep safe default.
                        return tasks.enumerated().map { idx, text in
                            BingoTask(taskId: "\(trimmedStepId)-T\(idx + 1)", mapsToStep: trimmedStepId, text: text, durationSec: 45, observable: "完成：\(text)", successProbability: 0.75)
                        }
                    }()

                    let derivedFrom = (step.derivedFromInterventionIds ?? [])
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }

                    return HabitGuideStep(
                        id: UUID(),
                        stepId: trimmedStepId,
                        derivedFromInterventionIds: derivedFrom,
                        title: trimmedTitle,
                        duration: trimmedDuration,
                        fallback: trimmedFallback,
                        category: trimmedCategory,
                        requiredBingoCount: required,
                        completedBingoCount: 0,
                        isCompleted: false,
                        bingoTasks: bingoTaskObjs
                    )
                }
                return HabitStageGuide(stage: stage.stage, steps: steps)
            }

        return HabitGuide(
            goal: goal,
            researchReport: researchReport,
            masteryDefinition: masteryDefinition,
            frictions: frictions,
            methodRoute: methodRoute,
            stages: stages,
            updatedAt: Date()
        )
    }

    private static func validateHabitGuideResponse(
        goal: String,
        researchReport: HabitResearchReport?,
        masteryDefinition: String,
        frictions: [String],
        methodRoute: [String],
        response: HabitGuideResponse
    ) throws {
        if masteryDefinition.isEmpty {
            throw OpenAIError.parse("缺少 masteryDefinition")
        }
        if frictions.count < 3 {
            throw OpenAIError.parse("frictions 少於 3 點")
        }
        if methodRoute.count < 3 {
            throw OpenAIError.parse("methodRoute 至少 3 點（目前：\(methodRoute.count)）")
        }

        // Force "research analysis" to be reflected in the methodRoute, not just time-scaling.
        // We keep this heuristic-based (keyword presence) to reduce failure rates while still enforcing intent.
        let routeText = methodRoute.joined(separator: "\n")
        func containsAny(_ keywords: [String]) -> Bool {
            keywords.contains { routeText.localizedCaseInsensitiveContains($0) }
        }
        // Triggers are helpful but shouldn't be mandatory (some users don't want a fixed cue).
        let hasTriggerDesign = containsAny(["觸發", "時機", "之後", "起床", "晚飯", "下班", "after", "when"])
        let hasVariants = containsAny(["替代方案", "替代", "如果", "或", "雨", "太累", "室內", "戶外", "instead", "otherwise", "variant"])
        let hasRecovery = containsAny(["中斷後回復", "中斷", "恢復", "回歸", "重新開始", "回來", "recover", "resume", "restart"])

        if !hasVariants {
            throw OpenAIError.parse("methodRoute 必須包含：替代方案（太累/雨天/時間少時的低配版本）")
        }
        if !hasRecovery {
            throw OpenAIError.parse("methodRoute 必須包含：中斷後回復（錯過後如何回歸最小版本）")
        }

        // If trigger design is missing, we allow it, but we can still nudge via prompt later.
        _ = hasTriggerDesign

        // Encourage frictions to be concrete (avoid overly generic one-liners).
        let genericFrictionPhrases = ["沒時間", "時間不足", "缺乏時間", "沒動力", "缺乏動力", "懶"]
        let genericFrictionCount = frictions.filter { f in
            genericFrictionPhrases.contains { p in f.contains(p) } && f.count <= 6
        }.count
        if genericFrictionCount >= 2 {
            throw OpenAIError.parse("frictions 太泛：請用具體情境/原因描述（例如下班太累、換衫麻煩、落雨冇地方）")
        }

        let stages = response.stages
        let stageSet = Set(stages.map { $0.stage })
        if stageSet != Set([0, 1, 2, 3, 4]) {
            throw OpenAIError.parse("stages 必須包含 stage=0..4")
        }

        // If the goal specifies a concrete target duration (e.g., "30 分鐘" / "30 minutes"),
        // enforce that stage 4 includes at least one step that clearly reaches that target.
        func extractTargetMinutes(from text: String) -> Int? {
            let patterns = ["(\\d{1,3})\\s*分鐘", "(\\d{1,3})\\s*分", "(\\d{1,3})\\s*minutes", "(\\d{1,3})\\s*mins", "(\\d{1,3})\\s*min"]
            for p in patterns {
                if let regex = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]) {
                    let range = NSRange(text.startIndex..<text.endIndex, in: text)
                    if let match = regex.firstMatch(in: text, options: [], range: range), match.numberOfRanges >= 2,
                       let r1 = Range(match.range(at: 1), in: text) {
                        return Int(text[r1])
                    }
                }
            }
            return nil
        }
        let targetMinutes = extractTargetMinutes(from: goal)
        var stage4CombinedText: String = ""
        let allowedInterventionIds: Set<String> = {
            guard let researchReport else { return [] }
            return Set(researchReport.interventionPlan.map { $0.interventionId.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        }()

        for s in stages {
            if s.steps.isEmpty {
                throw OpenAIError.parse("stage \(s.stage) steps 至少 1 個")
            }
            for step in s.steps {
                let sidRaw = (step.stepId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if sidRaw.isEmpty {
                    throw OpenAIError.parse("缺少 stepId")
                }

                // PASS2: steps must be traceable to PASS1 interventions.
                if !allowedInterventionIds.isEmpty {
                    let derived = (step.derivedFromInterventionIds ?? [])
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    if derived.isEmpty {
                        throw OpenAIError.parse("step \(sidRaw) 缺少 derivedFromInterventionIds")
                    }
                    let unknown = derived.filter { !allowedInterventionIds.contains($0) }
                    if !unknown.isEmpty {
                        throw OpenAIError.parse("step \(sidRaw) derivedFromInterventionIds 無效：\(unknown.joined(separator: ","))")
                    }
                }
                let expectedPrefix: String = {
                    switch s.stage {
                    case 0: return "S"
                    case 1: return "P"
                    case 2: return "L"
                    case 3: return "B"
                    case 4: return "R"
                    default: return ""
                    }
                }()
                if !sidRaw.hasPrefix(expectedPrefix) {
                    throw OpenAIError.parse("stepId \(sidRaw) 與 stage \(s.stage) 不匹配")
                }
                // Optional: ensure stepId has a positive index after the prefix (e.g., S1, P3)
                let idxStr = String(sidRaw.dropFirst(expectedPrefix.count))
                if let idx = Int(idxStr), idx <= 0 {
                    throw OpenAIError.parse("stepId \(sidRaw) 序號必須 >= 1")
                }

                let title = step.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let fallback = step.fallback.trimmingCharacters(in: .whitespacesAndNewlines)
                let duration = step.duration.trimmingCharacters(in: .whitespacesAndNewlines)
                if title.isEmpty || fallback.isEmpty {
                    throw OpenAIError.parse("step title/fallback 不可為空")
                }

                if s.stage == 4 {
                    stage4CombinedText += "\n" + title + " " + duration + " " + fallback
                    if let tasks = step.bingoTasks?.tasks {
                        stage4CombinedText += " " + tasks.map { $0.text }.joined(separator: " ")
                    }
                }

                let tasksField = step.bingoTasks?.tasks ?? []
                let tasks = tasksField.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                if tasks.isEmpty {
                    throw OpenAIError.parse("step \(sidRaw) bingoTasks 至少 1 個")
                }

                // PASS3 will enforce task-level traceability later.
                // For PASS2, we only require step-level traceability to reduce failure rate.
                _ = tasksField
                _ = allowedInterventionIds


                // requiredBingoCount: optional, but if provided it must be 1...3
                if let req = step.requiredBingoCount {
                    if !(1...3).contains(req) {
                        throw OpenAIError.parse("step \(sidRaw) requiredBingoCount 必須 1–3")
                    }
                }
            }
        }

        if let targetMinutes, targetMinutes >= 10 {
            let needle = String(targetMinutes)
            let hasTargetInStage4 = stage4CombinedText.contains(needle) && (
                stage4CombinedText.contains("分") || stage4CombinedText.localizedCaseInsensitiveContains("min")
            )
            if !hasTargetInStage4 {
                throw OpenAIError.parse("目標包含 \(targetMinutes) 分鐘，但 stage 4 必須包含可達到該時長的核心行為 step")
            }
        }

        // Basic hard bans
        let banned = ["每天", "每日", "天天", "培養觸發點", "建立儀式", "克服阻力", "開始行動", "嘗試一下", "做一個很小的步驟"]

        var allChunks: [String] = [masteryDefinition]
        allChunks.append(contentsOf: frictions)
        allChunks.append(contentsOf: methodRoute)
        for stage in stages {
            for step in stage.steps {
                var chunk = step.title + " " + step.fallback
                if let tasks = step.bingoTasks?.tasks {
                    chunk += " " + tasks.map { $0.text }.joined(separator: " ")
                }
                allChunks.append(chunk)
            }
        }
        let allText = allChunks.joined(separator: "\n")
        for word in banned {
            if allText.contains(word) {
                throw OpenAIError.parse("輸出包含禁詞：\(word)")
            }
        }
    }
}

struct HabitGuideResponse: Codable {
    var masteryDefinition: String?
    var frictions: [String]?
    var methodRoute: [String]?
    var stages: [HabitGuideStageResponse]
}

struct HabitGuideStageResponse: Codable {
    var stage: Int
    var stageName: String?  // Accept both index and name
    var steps: [HabitGuideStepResponse]
}

struct BingoTaskResponse: Codable {
    var taskId: String?
    var mapsToStep: String?
    var derivedFromInterventionIds: [String]?
    var text: String
    var durationSec: Int?
    var observable: String?
    var successProbability: Double?
}

struct BingoTasksField: Codable {
    var tasks: [BingoTaskResponse]

    init(tasks: [BingoTaskResponse]) {
        self.tasks = tasks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let objTasks = try? container.decode([BingoTaskResponse].self) {
            self.tasks = objTasks
            return
        }
        // Backward compatibility: allow [String]
        let legacy = (try? container.decode([String].self)) ?? []
        self.tasks = legacy.enumerated().map { idx, t in
            BingoTaskResponse(
                taskId: nil,
                mapsToStep: nil,
                derivedFromInterventionIds: nil,
                text: t,
                durationSec: nil,
                observable: nil,
                successProbability: nil
            )
        }
    }
}

struct HabitGuideStepResponse: Codable {
    var stepId: String?
    /// PASS2 traceability: which PASS1 interventions this step is derived from.
    var derivedFromInterventionIds: [String]?
    var title: String
    var duration: String
    var fallback: String
    var category: String?
    var requiredBingoCount: Int?
    var bingoTasks: BingoTasksField?
}

struct OpenAIResponse: Decodable {
    struct OutputItem: Decodable {
        let type: String
        let content: [Content]?
    }

    struct Content: Decodable {
        let type: String
        let text: String?
    }

    struct APIError: Decodable {
        let message: String
    }

    let output: [OutputItem]?
    let error: APIError?

    var outputText: String {
        guard let output = output else { return "" }
        return output.compactMap { item in
            item.content?
                .filter { $0.type == "output_text" }
                .compactMap { $0.text }
                .joined(separator: "\n")
        }
        .joined(separator: "\n")
    }
}

struct TaskResponse: Decodable {
    let tasks: [String]
}

struct TaskPoolResponse: Decodable {
    let goalTasks: [String: [String]]
    let extraTasks: [String]
}

struct CoinEstimateResponse: Decodable {
    let coins: Int
}

enum OpenAIError: LocalizedError {
    case network(String)
    case server(String)
    case parse(String)

    var errorDescription: String? {
        switch self {
        case .network(let message):
            return message
        case .server(let message):
            return message
        case .parse(let message):
            return message
        }
    }
}
