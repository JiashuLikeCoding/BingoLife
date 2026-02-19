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

    private func generateGoalNormalization(goal: String, previousError: String? = nil) async throws -> GoalNormalization {
        let previousErrorBlock: String = {
            guard let previousError, !previousError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
            return "\n【上次輸出未通過驗證】\n\(previousError)\n請你修正後重新輸出，並確保完全符合本次的格式要求。\n"
        }()

        let prompt = """
        你是「Behavioral Scientist + Skill Acquisition Architect + Positive Psychology Expert」。
        你要處理任何使用者輸入的目標 goal，但此回合只允許做 STEP 0：目標正規化（抽象轉換）。
        \(previousErrorBlock)

        【硬性禁止】
        - 禁止產生任何步驟、任務、行動建議、練習、計畫、階段名稱、bingoTasks、stages、Habit Map。
        - 禁止使用或重複 cadence 字：每天、每日、天天（即使使用者 goal 有，也不可在輸出中出現這些字）。
        - 禁止 KPI/連續天數/時間遞增模板語氣（例如：連續X天、每天X分鐘、3→10→30）。

        【輸出格式】
        - 只輸出「單一 JSON 物件」，不得有任何額外文字、不得 markdown、不得 code block。
        - 若 goal 過於空泛或不可解析，仍必須輸出 JSON，但用 needsClarification:true 並在 clarifyingQuestion 問 1 個最關鍵澄清問題（仍禁止 steps/tasks）。

        【你要做的事】
        把 goal 轉換成能力本質與身份形態，並描述長期掌握狀態（可觀察、非時間、非數量、非連續天數）。

        【輸出 schema】
        {
          "step": 0,
          "needsClarification": false,
          "clarifyingQuestion": "",
          "normalizedSkill": "能力本質描述（不是行為表面；不含 cadence/KPI 語氣）",
          "skillType": "體能 | 認知 | 情緒 | 自律 | 技術 | 混合型",
          "identityForm": "身份形態（我是…的人）",
          "masteryState": "掌握狀態（可觀察、可描述的行為表現；非時間、非數量、非連續天數）",
          "goalSanitizedForDownstream": "移除 cadence/KPI 語氣後的乾淨目標字串（不可包含 每天/每日/天天）"
        }

        【使用者 goal】
        \(goal)

        只回傳 JSON。
        """

        let requestBody: [String: Any] = [
            "model": model,
            "input": [
                ["role": "system", "content": "You are a helpful assistant. Respond in JSON only."],
                ["role": "user", "content": prompt]
            ],
            "text": ["format": ["type": "json_object"]],
            "max_output_tokens": 600
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

        let normalization: GoalNormalization
        do {
            normalization = try JSONDecoder().decode(GoalNormalization.self, from: jsonData)
        } catch {
            let preview = text.prefix(400)
            throw OpenAIError.parse("STEP0 JSON 解析失敗：\(error.localizedDescription)\npreview: \(preview)")
        }

        // STEP0 validation (strict, since it drives downstream prompts)
        if normalization.step != 0 {
            throw OpenAIError.parse("STEP0 step 必須為 0")
        }
        let banned = ["每天", "每日", "天天"]
        let allText = [
            normalization.clarifyingQuestion,
            normalization.normalizedSkill,
            normalization.skillType,
            normalization.identityForm,
            normalization.masteryState,
            normalization.goalSanitizedForDownstream
        ].joined(separator: "\n")
        for w in banned where allText.contains(w) {
            throw OpenAIError.parse("STEP0 輸出包含禁字：\(w)")
        }

        if normalization.needsClarification {
            let q = normalization.clarifyingQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
            if q.isEmpty {
                throw OpenAIError.parse("STEP0 needsClarification=true 時 clarifyingQuestion 不可為空")
            }
            throw OpenAIError.parse("STEP0 需要澄清：\(q)")
        }

        func nonEmpty(_ s: String) -> Bool { !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !nonEmpty(normalization.normalizedSkill) { throw OpenAIError.parse("STEP0 normalizedSkill 不可為空") }
        if !nonEmpty(normalization.identityForm) { throw OpenAIError.parse("STEP0 identityForm 不可為空") }
        if !nonEmpty(normalization.masteryState) { throw OpenAIError.parse("STEP0 masteryState 不可為空") }
        if !nonEmpty(normalization.goalSanitizedForDownstream) { throw OpenAIError.parse("STEP0 goalSanitizedForDownstream 不可為空") }

        return normalization
    }

    private func generateHabitResearchReport(goal: String, normalization: GoalNormalization, previousError: String? = nil) async throws -> HabitResearchReport {
        let sanitizedGoal = normalization.goalSanitizedForDownstream.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeGoal = sanitizedGoal.isEmpty ? goal : sanitizedGoal

        let previousErrorBlock: String = {
            guard let previousError, !previousError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
            return "\n【上次輸出未通過驗證】\n\(previousError)\n請你修正後重新輸出，並確保完全符合本次的數量與格式要求。\n"
        }()

        let prompt = """
        你是行為科學導向的習慣養成研究員與產品設計師。
        請先為「\(safeGoal)」寫一份研究報告（PASS 1），用繁體中文，並輸出 JSON。
        \(previousErrorBlock)

        【STEP 0 正規化結果（僅供理解，不要照抄 cadence/KPI）】
        - normalizedSkill：\(normalization.normalizedSkill)
        - skillType：\(normalization.skillType)
        - identityForm：\(normalization.identityForm)
        - masteryState：\(normalization.masteryState)

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

    private func generateSkillModel(normalization: GoalNormalization, researchReport: HabitResearchReport, previousError: String? = nil) async throws -> SkillModelReport {
        let safeGoal = normalization.goalSanitizedForDownstream.trimmingCharacters(in: .whitespacesAndNewlines)
        let previousErrorBlock: String = {
            guard let previousError, !previousError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
            return "\n【上次輸出未通過驗證】\n\(previousError)\n請你修正後重新輸出，並確保完全符合本次的數量與格式要求。\n"
        }()

        let researchHints: String = {
            let fr = researchReport.frictionMechanisms.prefix(4).map { "- \($0)" }.joined(separator: "\n")
            let fm = researchReport.failureModes.prefix(3).map { "- \($0)" }.joined(separator: "\n")
            let itv = researchReport.interventionPlan.prefix(6).map { "- \($0.interventionId): \($0.title)" }.joined(separator: "\n")
            return "阻力機制：\n\(fr)\n\n失敗模式：\n\(fm)\n\n既有干預策略：\n\(itv)"
        }()

        let prompt = """
        你是「Behavioral Scientist + Skill Acquisition Architect + Positive Psychology Expert」。
        你要處理 STEP 1 — EXPERT RESEARCH（專家研究）。此回合只允許輸出 skillModel（能力建模），禁止任何步驟/任務/行動/計畫。
        \(previousErrorBlock)

        【硬性禁止】
        - 禁止產生任何 steps / tasks / 行動指令 / 練習項目 / 階段名稱（例如 Stage 0-4）/ bingoTasks / Habit Map。
        - 禁止時間遞增模板（3→10→30）。
        - 禁止輸出 cadence 字：每天、每日、天天。
        - 禁止 KPI/連續天數/時間作為掌握定義。

        【輸入（STEP0 + PASS1 摘要）】
        goal（sanitize 後）：\(safeGoal)
        normalizedSkill：\(normalization.normalizedSkill)
        identityForm：\(normalization.identityForm)
        masteryState：\(normalization.masteryState)

        PASS1 研究提示（僅供理解，不要輸出行動）：
        \(researchHints)

        【輸出格式】
        - 只輸出單一 JSON 物件（不要額外文字）

        【輸出 schema】
        {
          "step": 1,
          "skillModel": {
            "requiredCapabilities": [
              { "capabilityId": "C1", "name": "...", "description": "...", "dependsOn": [] }
            ],
            "dependencyOrder": ["C1","C2","C3"],
            "developmentCurve": "...",
            "failurePatterns": [
              { "failureId": "F1", "pattern": "...", "mechanism": "..." }
            ],
            "leveragePoints": [
              { "leverageId": "L1", "targetsCapability": "C1", "mechanism": "...", "impact": "..." }
            ]
          }
        }

        【內容要求】
        - requiredCapabilities：至少 3 個（C1..C#），每個 dependsOn 只能引用已存在的 capabilityId。
        - dependencyOrder：至少 3 個，且每個都必須出現在 requiredCapabilities。
        - failurePatterns：至少 3 個（F1..），寫具體失敗曲線與心理機制（不是解法）。
        - leveragePoints：至少 4 個（L1..），每個 targetsCapability 必須引用存在的 capabilityId。

        只回傳 JSON。
        """

        struct SkillModelEnvelope: Decodable {
            let step: Int
            let skillModel: SkillModelReport
        }

        let requestBody: [String: Any] = [
            "model": model,
            "input": [
                ["role": "system", "content": "You are a helpful assistant. Respond in JSON only."],
                ["role": "user", "content": prompt]
            ],
            "text": ["format": ["type": "json_object"]],
            "max_output_tokens": 1600
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: [])
        request.timeoutInterval = 120

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OpenAIError.network("無法取得回應") }
        if !(200...299).contains(http.statusCode) {
            let message = String(data: data, encoding: .utf8) ?? "狀態碼 \(http.statusCode)"
            throw OpenAIError.server(message)
        }

        let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        if let error = decoded.error { throw OpenAIError.server(error.message) }
        let text = decoded.outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let jsonData = text.data(using: .utf8) else {
            throw OpenAIError.parse("STEP1 回應內容為空")
        }

        let env: SkillModelEnvelope
        do {
            env = try JSONDecoder().decode(SkillModelEnvelope.self, from: jsonData)
        } catch {
            let preview = text.prefix(400)
            throw OpenAIError.parse("STEP1 JSON 解析失敗：\(error.localizedDescription)\npreview: \(preview)")
        }

        if env.step != 1 { throw OpenAIError.parse("STEP1 step 必須為 1") }

        let banned = ["每天", "每日", "天天"]
        let allText = [
            env.skillModel.developmentCurve,
            env.skillModel.requiredCapabilities.map { "\($0.capabilityId) \($0.name) \($0.description) \($0.dependsOn.joined(separator: ","))" }.joined(separator: "\n"),
            env.skillModel.failurePatterns.map { "\($0.failureId) \($0.pattern) \($0.mechanism)" }.joined(separator: "\n"),
            env.skillModel.leveragePoints.map { "\($0.leverageId) \($0.targetsCapability) \($0.mechanism) \($0.impact)" }.joined(separator: "\n")
        ].joined(separator: "\n")
        for w in banned where allText.contains(w) {
            throw OpenAIError.parse("STEP1 輸出包含禁字：\(w)")
        }

        // Basic structure validation
        if env.skillModel.requiredCapabilities.count < 3 { throw OpenAIError.parse("STEP1 requiredCapabilities 少於 3") }
        if env.skillModel.dependencyOrder.count < 3 { throw OpenAIError.parse("STEP1 dependencyOrder 少於 3") }
        if env.skillModel.failurePatterns.count < 3 { throw OpenAIError.parse("STEP1 failurePatterns 少於 3") }
        if env.skillModel.leveragePoints.count < 4 { throw OpenAIError.parse("STEP1 leveragePoints 少於 4") }

        let capIds = Set(env.skillModel.requiredCapabilities.map { $0.capabilityId.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        if capIds.count < 3 { throw OpenAIError.parse("STEP1 capabilityId 重複或不足") }
        for c in env.skillModel.requiredCapabilities {
            for d in c.dependsOn {
                if !d.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !capIds.contains(d) {
                    throw OpenAIError.parse("STEP1 dependsOn 引用不存在 capabilityId：\(d)")
                }
            }
        }
        for id in env.skillModel.dependencyOrder {
            if !capIds.contains(id) {
                throw OpenAIError.parse("STEP1 dependencyOrder 引用不存在 capabilityId：\(id)")
            }
        }
        let levIds = Set(env.skillModel.leveragePoints.map { $0.leverageId.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        if levIds.count < env.skillModel.leveragePoints.count { throw OpenAIError.parse("STEP1 leverageId 不可重複") }
        for lp in env.skillModel.leveragePoints {
            if !capIds.contains(lp.targetsCapability) {
                throw OpenAIError.parse("STEP1 leveragePoint.targetsCapability 引用不存在 capabilityId：\(lp.targetsCapability)")
            }
        }

        return env.skillModel
    }

    private func generateCapabilityStages(normalization: GoalNormalization, skillModel: SkillModelReport, previousError: String? = nil) async throws -> [CapabilityStage] {
        let safeGoal = normalization.goalSanitizedForDownstream.trimmingCharacters(in: .whitespacesAndNewlines)
        let previousErrorBlock: String = {
            guard let previousError, !previousError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
            return "\n【上次輸出未通過驗證】\n\(previousError)\n請你修正後重新輸出，並確保完全符合本次的格式要求。\n"
        }()

        let capList = skillModel.requiredCapabilities.map { "- \($0.capabilityId): \($0.name)｜\($0.description)" }.joined(separator: "\n")
        let dep = skillModel.dependencyOrder.joined(separator: ", ")

        let prompt = """
        你是「Behavioral Scientist + Skill Acquisition Architect + Positive Psychology Expert」。
        你要處理 STEP 2 — CAPABILITY STAGES（能力階段建構）。此回合只允許建立能力發展階段（不是時間階段），禁止任何步驟/任務/行動。
        \(previousErrorBlock)

        【硬性禁止】
        - 禁止產生任何 steps / tasks / 行動指令 / 練習項目 / Habit Map。
        - 禁止用時間/數量遞增作為進階依據。
        - 禁止輸出 cadence 字：每天、每日、天天。

        【輸入】
        goal（sanitize 後）：\(safeGoal)
        normalizedSkill：\(normalization.normalizedSkill)
        masteryState：\(normalization.masteryState)

        requiredCapabilities：
        \(capList)
        dependencyOrder：\(dep)

        【輸出格式】
        - 只輸出單一 JSON 物件（不要額外文字）

        【輸出 schema】
        { "step": 2, "capabilityStages": [ { "stage": 0, "focusCapability": "C1", "psychologicalGoal": "...", "competenceGoal": "...", "completionIndicator": "..." } ] }

        【內容要求】
        - capabilityStages 至少 3 個 stage，stage 必須從 0 開始連續遞增。
        - focusCapability 必須是存在的 capabilityId。
        - completionIndicator 必須是「可觀察能力徵兆」，非 KPI/時間/次數。

        只回傳 JSON。
        """

        struct StagesEnvelope: Decodable {
            let step: Int
            let capabilityStages: [CapabilityStage]
        }

        let requestBody: [String: Any] = [
            "model": model,
            "input": [
                ["role": "system", "content": "You are a helpful assistant. Respond in JSON only."],
                ["role": "user", "content": prompt]
            ],
            "text": ["format": ["type": "json_object"]],
            "max_output_tokens": 1400
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: [])
        request.timeoutInterval = 120

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OpenAIError.network("無法取得回應") }
        if !(200...299).contains(http.statusCode) {
            let message = String(data: data, encoding: .utf8) ?? "狀態碼 \(http.statusCode)"
            throw OpenAIError.server(message)
        }

        let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        if let error = decoded.error { throw OpenAIError.server(error.message) }
        let text = decoded.outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let jsonData = text.data(using: .utf8) else {
            throw OpenAIError.parse("STEP2 回應內容為空")
        }

        let env: StagesEnvelope
        do {
            env = try JSONDecoder().decode(StagesEnvelope.self, from: jsonData)
        } catch {
            let preview = text.prefix(400)
            throw OpenAIError.parse("STEP2 JSON 解析失敗：\(error.localizedDescription)\npreview: \(preview)")
        }

        if env.step != 2 { throw OpenAIError.parse("STEP2 step 必須為 2") }

        let banned = ["每天", "每日", "天天"]
        let allText = env.capabilityStages.map { "\($0.stage) \($0.focusCapability) \($0.psychologicalGoal) \($0.competenceGoal) \($0.completionIndicator)" }.joined(separator: "\n")
        for w in banned where allText.contains(w) { throw OpenAIError.parse("STEP2 輸出包含禁字：\(w)") }

        if env.capabilityStages.count < 3 { throw OpenAIError.parse("STEP2 capabilityStages 少於 3") }

        let capIds = Set(skillModel.requiredCapabilities.map { $0.capabilityId })
        var expectedStage = 0
        for st in env.capabilityStages {
            if st.stage != expectedStage { throw OpenAIError.parse("STEP2 stage 必須從 0 連續遞增（期望 \(expectedStage)，得到 \(st.stage)）") }
            expectedStage += 1
            if !capIds.contains(st.focusCapability) {
                throw OpenAIError.parse("STEP2 focusCapability 引用不存在 capabilityId：\(st.focusCapability)")
            }
            if st.completionIndicator.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw OpenAIError.parse("STEP2 completionIndicator 不可為空")
            }
        }

        return env.capabilityStages
    }

    private func generateHabitArchitecture(normalization: GoalNormalization, skillModel: SkillModelReport, capabilityStages: [CapabilityStage], previousError: String? = nil) async throws -> HabitArchitecture {
        let safeGoal = normalization.goalSanitizedForDownstream.trimmingCharacters(in: .whitespacesAndNewlines)
        let previousErrorBlock: String = {
            guard let previousError, !previousError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
            return "\n【上次輸出未通過驗證】\n\(previousError)\n請你修正後重新輸出，並確保完全符合本次的格式要求。\n"
        }()

        let caps = skillModel.requiredCapabilities.map { "- \($0.capabilityId): \($0.name)" }.joined(separator: "\n")
        let levs = skillModel.leveragePoints.map { "- \($0.leverageId) -> \($0.targetsCapability): \($0.mechanism)" }.joined(separator: "\n")
        let stageRefs = capabilityStages.map { "- stage \($0.stage): focus \($0.focusCapability)" }.joined(separator: "\n")

        let prompt = """
        你是「Behavioral Scientist + Skill Acquisition Architect + Positive Psychology Expert」。
        你要處理 STEP 3 — BEHAVIOR COMPILATION（行為編譯）。現在才允許生成具體行為。
        \(previousErrorBlock)

        【硬性禁止】
        - 禁止時間遞增模板（3→10→30）。
        - 禁止輸出 cadence 字：每天、每日、天天（注意：連「舉例」都唔可以出現）。
        - 禁止 KPI/連續天數/時間作為衡量。
        - 你輸出前必須自我檢查：全文搜尋「每天」「每日」「天天」三個字，確保 0 次出現。

        【輸入】
        goal（sanitize 後）：\(safeGoal)
        identityForm：\(normalization.identityForm)
        masteryState：\(normalization.masteryState)

        capabilities：
        \(caps)

        leveragePoints：
        \(levs)

        capabilityStages：
        \(stageRefs)

        【規則】
        - 每個行為必須引用 capabilityId（capabilityRef）
        - 每個行為必須引用 leverageId（leverageRef）
        - 每個行為必須說明 whyBuildsCapability（機制層）
        - 每個行為必須說明 identityImpact（身份層）
        - 行為數量最少但必要：每階段 1–2 個

        【輸出格式】
        - 只輸出單一 JSON 物件（不要額外文字）

        【輸出 schema】
        {
          "step": 3,
          "habitArchitecture": {
            "stages": [
              {
                "stage": 0,
                "supportsCapability": "C1",
                "behaviors": [
                  {
                    "behaviorId": "B1",
                    "title": "具體行為句",
                    "capabilityRef": "C1",
                    "leverageRef": "L1",
                    "whyBuildsCapability": "...",
                    "identityImpact": "..."
                  }
                ]
              }
            ]
          }
        }

        只回傳 JSON。
        """

        struct ArchEnvelope: Decodable {
            let step: Int
            let habitArchitecture: HabitArchitecture
        }

        let requestBody: [String: Any] = [
            "model": model,
            "input": [
                ["role": "system", "content": "You are a helpful assistant. Respond in JSON only."],
                ["role": "user", "content": prompt]
            ],
            "text": ["format": ["type": "json_object"]],
            "max_output_tokens": 1600
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: [])
        request.timeoutInterval = 120

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OpenAIError.network("無法取得回應") }
        if !(200...299).contains(http.statusCode) {
            let message = String(data: data, encoding: .utf8) ?? "狀態碼 \(http.statusCode)"
            throw OpenAIError.server(message)
        }

        let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        if let error = decoded.error { throw OpenAIError.server(error.message) }
        let text = decoded.outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let jsonData = text.data(using: .utf8) else {
            throw OpenAIError.parse("STEP3 回應內容為空")
        }

        let env: ArchEnvelope
        do {
            env = try JSONDecoder().decode(ArchEnvelope.self, from: jsonData)
        } catch {
            let preview = text.prefix(400)
            throw OpenAIError.parse("STEP3 JSON 解析失敗：\(error.localizedDescription)\npreview: \(preview)")
        }

        if env.step != 3 { throw OpenAIError.parse("STEP3 step 必須為 3") }

        let banned = ["每天", "每日", "天天"]
        let allText = env.habitArchitecture.stages.flatMap { st in
            st.behaviors.map { b in "\(b.behaviorId) \(b.title) \(b.capabilityRef) \(b.leverageRef) \(b.whyBuildsCapability) \(b.identityImpact)" }
        }.joined(separator: "\n")
        for w in banned where allText.contains(w) { throw OpenAIError.parse("STEP3 輸出包含禁字：\(w)") }

        let capIds = Set(skillModel.requiredCapabilities.map { $0.capabilityId })
        let levIds = Set(skillModel.leveragePoints.map { $0.leverageId })

        if env.habitArchitecture.stages.count < max(1, capabilityStages.count) {
            throw OpenAIError.parse("STEP3 habitArchitecture.stages 數量不足（需要覆蓋 STEP2 stages）")
        }

        for st in env.habitArchitecture.stages {
            if !capIds.contains(st.supportsCapability) {
                throw OpenAIError.parse("STEP3 supportsCapability 引用不存在 capabilityId：\(st.supportsCapability)")
            }
            if st.behaviors.isEmpty || st.behaviors.count > 2 {
                throw OpenAIError.parse("STEP3 stage \(st.stage) behaviors 必須為 1–2 個")
            }
            for b in st.behaviors {
                if !capIds.contains(b.capabilityRef) { throw OpenAIError.parse("STEP3 capabilityRef 引用不存在：\(b.capabilityRef)") }
                if !levIds.contains(b.leverageRef) { throw OpenAIError.parse("STEP3 leverageRef 引用不存在：\(b.leverageRef)") }
                if b.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw OpenAIError.parse("STEP3 behavior title 不可為空") }
                if b.whyBuildsCapability.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw OpenAIError.parse("STEP3 whyBuildsCapability 不可為空") }
                if b.identityImpact.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw OpenAIError.parse("STEP3 identityImpact 不可為空") }
            }
        }

        return env.habitArchitecture
    }

    private func generateReinforcementUnits(normalization: GoalNormalization, skillModel: SkillModelReport, habitArchitecture: HabitArchitecture, previousError: String? = nil) async throws -> [ReinforcementUnit] {
        let safeGoal = normalization.goalSanitizedForDownstream.trimmingCharacters(in: .whitespacesAndNewlines)

        // Build capability catalog + identity hints from STEP3 behaviors (so STEP4 tasks can be diverse but still goal-adjacent).
        let capabilityCatalog: String = skillModel.requiredCapabilities
            .map { c in "- \(c.capabilityId): \(c.name)｜\(c.description)" }
            .joined(separator: "\n")

        let identityHintsByCapability: [String: [String]] = {
            var map: [String: [String]] = [:]
            let allBehaviors = habitArchitecture.stages.flatMap { $0.behaviors }
            for b in allBehaviors {
                let cap = b.capabilityRef
                var arr = map[cap, default: []]
                let hint = b.identityImpact.trimmingCharacters(in: .whitespacesAndNewlines)
                if !hint.isEmpty, !arr.contains(hint) {
                    arr.append(hint)
                }
                map[cap] = arr
            }
            return map
        }()

        let identityHintsText: String = {
            var lines: [String] = []
            for cap in skillModel.requiredCapabilities.map({ $0.capabilityId }) {
                let hints = (identityHintsByCapability[cap] ?? []).prefix(3)
                if hints.isEmpty { continue }
                lines.append("- \(cap): \(hints.joined(separator: " / "))")
            }
            return lines.joined(separator: "\n")
        }()

        let capIds: [String] = skillModel.requiredCapabilities.map { $0.capabilityId }
        let capIdSet = Set(capIds)
        let requiredFormsOrdered: [String] = ["身體動作型", "語言輸出型", "環境改造型", "微決策型", "社交/外部承諾型"]
        let requiredFormsSet = Set(requiredFormsOrdered)
        let expectedUnitCount = capIds.count * requiredFormsOrdered.count

        struct Envelope: Decodable {
            let step: Int
            let reinforcementUnits: [ReinforcementUnit]
        }

        func unitKey(_ u: ReinforcementUnit) -> String {
            let cap = (u.capabilityRef ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let form = (u.form ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(cap)|\(form)"
        }

        func scanBanned(_ units: [ReinforcementUnit]) throws {
            let banned = ["每天", "每日", "天天"]
            let allText = units.flatMap { u in
                let cap = u.capabilityRef ?? ""
                let form = u.form ?? ""
                return u.bingoTasks.map { t in "\(cap) \(form) \(t.taskId) \(t.text) \(t.observable) \(t.reinforcesCapability) \(t.reinforcesIdentity)" }
            }.joined(separator: "\n")
            for w in banned where allText.contains(w) { throw OpenAIError.parse("STEP4 輸出包含禁字：\(w)") }
        }

        func validateUnits(_ units: [ReinforcementUnit], strictCount: Bool) throws {
            if units.isEmpty { throw OpenAIError.parse("STEP4 reinforcementUnits 不可為空") }
            if strictCount, units.count != expectedUnitCount {
                throw OpenAIError.parse("STEP4 reinforcementUnits 數量必須為 \(expectedUnitCount)（capabilities=\(capIds.count) × forms=\(requiredFormsOrdered.count)），目前：\(units.count)")
            }

            var formsByCap: [String: Set<String>] = [:]
            var coveredCaps: Set<String> = []
            var seenKeys: Set<String> = []

            for unit in units {
                let capRef = (unit.capabilityRef ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if capRef.isEmpty { throw OpenAIError.parse("STEP4 capabilityRef 不可為空") }
                if !capIdSet.contains(capRef) { throw OpenAIError.parse("STEP4 capabilityRef 引用不存在 capabilityId：\(capRef)") }
                coveredCaps.insert(capRef)

                let form = (unit.form ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if form.isEmpty { throw OpenAIError.parse("STEP4 \(capRef) form 不可為空") }
                if !requiredFormsSet.contains(form) { throw OpenAIError.parse("STEP4 \(capRef) form 不在允許列表：\(form)") }

                let key = "\(capRef)|\(form)"
                if seenKeys.contains(key) { throw OpenAIError.parse("STEP4 \(capRef) form 重複：\(form)") }
                seenKeys.insert(key)

                var formSet = formsByCap[capRef, default: []]
                formSet.insert(form)
                formsByCap[capRef] = formSet

                if unit.bingoTasks.isEmpty { throw OpenAIError.parse("STEP4 \(capRef) [\(form)] bingoTasks 不可為空") }
                for t in unit.bingoTasks {
                    if t.taskId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw OpenAIError.parse("STEP4 taskId 不可為空") }
                    if t.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw OpenAIError.parse("STEP4 \(capRef) text 不可為空") }
                    if t.observable.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw OpenAIError.parse("STEP4 \(capRef) observable 不可為空") }
                    if t.reinforcesCapability.trimmingCharacters(in: .whitespacesAndNewlines) != capRef {
                        throw OpenAIError.parse("STEP4 \(capRef) reinforcesCapability 必須等於 capabilityRef（得到：\(t.reinforcesCapability)）")
                    }
                    if t.reinforcesIdentity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        throw OpenAIError.parse("STEP4 \(capRef) reinforcesIdentity 不可為空")
                    }
                }
            }

            if strictCount {
                if coveredCaps.count < capIdSet.count {
                    throw OpenAIError.parse("STEP4 reinforcementUnits 必須覆蓋所有 capabilities（缺少：\(capIdSet.subtracting(coveredCaps).joined(separator: ", "))）")
                }
                for cap in capIdSet {
                    let forms = formsByCap[cap] ?? []
                    if forms != requiredFormsSet {
                        let missing = requiredFormsSet.subtracting(forms).joined(separator: ", ")
                        let extra = forms.subtracting(requiredFormsSet).joined(separator: ", ")
                        throw OpenAIError.parse("STEP4 \(cap) 必須剛好包含 5 種形式；缺少：\(missing.isEmpty ? "無" : missing)；多出：\(extra.isEmpty ? "無" : extra)")
                    }
                }
            }
        }

        func missingPairs(_ units: [ReinforcementUnit]) -> [(cap: String, form: String)] {
            var present: Set<String> = []
            for u in units {
                let cap = (u.capabilityRef ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let form = (u.form ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if cap.isEmpty || form.isEmpty { continue }
                present.insert("\(cap)|\(form)")
            }
            var out: [(String, String)] = []
            for cap in capIds {
                for form in requiredFormsOrdered {
                    let key = "\(cap)|\(form)"
                    if !present.contains(key) {
                        out.append((cap, form))
                    }
                }
            }
            return out
        }

        func requestSTEP4(prompt: String, maxTokens: Int) async throws -> [ReinforcementUnit] {
            let requestBody: [String: Any] = [
                "model": model,
                "input": [
                    ["role": "system", "content": "You are a helpful assistant. Respond in JSON only."],
                    ["role": "user", "content": prompt]
                ],
                "text": ["format": ["type": "json_object"]],
                "max_output_tokens": maxTokens
            ]

            var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
            request.httpMethod = "POST"
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: [])
            request.timeoutInterval = 120

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw OpenAIError.network("無法取得回應") }
            if !(200...299).contains(http.statusCode) {
                let message = String(data: data, encoding: .utf8) ?? "狀態碼 \(http.statusCode)"
                throw OpenAIError.server(message)
            }
            let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
            if let error = decoded.error { throw OpenAIError.server(error.message) }
            let text = decoded.outputText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, let jsonData = text.data(using: .utf8) else { throw OpenAIError.parse("STEP4 回應內容為空") }

            let env: Envelope
            do {
                env = try JSONDecoder().decode(Envelope.self, from: jsonData)
            } catch {
                let preview = text.prefix(400)
                throw OpenAIError.parse("STEP4 JSON 解析失敗：\(error.localizedDescription)\npreview: \(preview)")
            }
            if env.step != 4 { throw OpenAIError.parse("STEP4 step 必須為 4") }
            return env.reinforcementUnits
        }

        // Prompt 1: full generation.
        let previousErrorBlock: String = {
            guard let previousError, !previousError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
            return "\n【上次輸出未通過驗證】\n\(previousError)\n請你修正後重新輸出，並確保完全符合本次的格式要求。\n"
        }()

        let basePrompt = """
        你是「Behavioral Scientist + Skill Acquisition Architect」。
        你要處理 STEP 4 — REINFORCEMENT COMPILATION（強化單位）。
        你要為每個 capability 生成 5 種不同形式的強化單位（不得重複形式）。
        \(previousErrorBlock)

        【硬性禁止】
        - 禁止輸出 cadence 字：每天、每日、天天。
        - 禁止新增新邏輯/新策略/新行為方向；只能做「強化單位」（≤60秒、一個完整動作循環）。
        - 禁止把 step/title 原句換字當 task；要更細、更可立即做。

        【輸入】
        goal（sanitize 後）：\(safeGoal)
        identityForm：\(normalization.identityForm)
        capabilities（必須全部覆蓋）：
        \(capabilityCatalog)

        identityImpact hints（幫你寫 reinforcesIdentity；可參考但勿照抄口號）：
        \(identityHintsText)

        【形式（每個 capability 必須剛好各 1 個；不得重複）】
        - 身體動作型
        - 語言輸出型
        - 環境改造型
        - 微決策型
        - 社交/外部承諾型（任何外部承諾載體都得：便條紙/鬧鐘命名/發訊息給自己/打卡一句話；但仍要 ≤60秒）

        【規則】
        - 每個 reinforcementUnit 對應一個 capability（capabilityRef）。
        - 每個 reinforcementUnit 必須標示 form（以上五選一）。
        - 每個 reinforcementUnit 至少 1 個 bingoTask。
        - 每個 bingoTask 必須 ≤60 秒或一個完整動作循環。
        - 每個 bingoTask 的 reinforcesCapability 必須等於 capabilityRef。
        - 每個 bingoTask 必須有 reinforcesIdentity（完成代表我是…），語氣務實、可落地。

        【輸出】
        只輸出 JSON：
        {
          "step": 4,
          "reinforcementUnits": [
            {
              "capabilityRef": "C1",
              "form": "身體動作型",
              "bingoTasks": [
                {
                  "taskId": "C1-PHYS-1",
                  "text": "≤60秒具體行為",
                  "observable": "完成標誌",
                  "reinforcesCapability": "C1",
                  "reinforcesIdentity": "完成代表我是..."
                }
              ]
            }
          ]
        }

        【你輸出前必須自我檢查】
        - 對每個 capability：5 種 form 都齊全，且無重複。
        - 每個 unit 的 bingoTasks 至少 1 個。

        只回傳 JSON。
        """

        // Generate + "patch missing" (補齊式生成) to avoid transient partial outputs.
        var merged: [ReinforcementUnit] = []

        do {
            merged = try await requestSTEP4(prompt: basePrompt, maxTokens: 1800)
            try scanBanned(merged)
            try validateUnits(merged, strictCount: false)
        } catch {
            throw error
        }

        // Patch passes: ask only for missing (capabilityRef, form) pairs and then merge.
        for _ in 0..<3 {
            let missing = missingPairs(merged)
            if missing.isEmpty { break }

            let missingLines = missing.map { "- \($0.cap)｜\($0.form)" }.joined(separator: "\n")
            let existingKeys = merged.map { unitKey($0) }.joined(separator: ", ")

            let patchPrompt = """
            你是「Behavioral Scientist + Skill Acquisition Architect」。
            你正在補齊 STEP4 reinforcementUnits。

            【硬性禁止】
            - 禁止輸出 cadence 字：每天、每日、天天。
            - 只生成缺少的 (capabilityRef, form) 單位；不要重複已存在的。

            goal（sanitize 後）：\(safeGoal)
            identityForm：\(normalization.identityForm)
            capabilities：
            \(capabilityCatalog)

            forms（固定五種）：\(requiredFormsOrdered.joined(separator: " / "))

            已存在的 keys（capabilityRef|form）：\(existingKeys)

            你必須只生成以下缺少的組合（每行 1 個 unit，且 form 必須完全一致）：
            \(missingLines)

            【輸出格式】只輸出 JSON：
            {
              "step": 4,
              "reinforcementUnits": [
                {
                  "capabilityRef": "C1",
                  "form": "身體動作型",
                  "bingoTasks": [
                    {
                      "taskId": "C1-PHYS-1",
                      "text": "≤60秒具體行為",
                      "observable": "完成標誌",
                      "reinforcesCapability": "C1",
                      "reinforcesIdentity": "完成代表我是..."
                    }
                  ]
                }
              ]
            }

            只回傳 JSON。
            """

            let patchUnits = try await requestSTEP4(prompt: patchPrompt, maxTokens: 1200)
            try scanBanned(patchUnits)
            try validateUnits(patchUnits, strictCount: false)

            var byKey: [String: ReinforcementUnit] = Dictionary(uniqueKeysWithValues: merged.map { (unitKey($0), $0) })
            for u in patchUnits {
                let k = unitKey(u)
                if byKey[k] == nil {
                    byKey[k] = u
                }
            }
            merged = Array(byKey.values)
        }

        // Final strict validation.
        try scanBanned(merged)
        try validateUnits(merged, strictCount: true)

        return merged
    }

    private func generateRecoverySystem(normalization: GoalNormalization, researchReport: HabitResearchReport, previousError: String? = nil) async throws -> RecoverySystem {
        let safeGoal = normalization.goalSanitizedForDownstream.trimmingCharacters(in: .whitespacesAndNewlines)
        let previousErrorBlock: String = {
            guard let previousError, !previousError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
            return "\n【上次輸出未通過驗證】\n\(previousError)\n請你修正後重新輸出，並確保完全符合本次的格式要求。\n"
        }()

        let fr = researchReport.frictionMechanisms.prefix(4).map { "- \($0)" }.joined(separator: "\n")
        let fm = researchReport.failureModes.prefix(3).map { "- \($0)" }.joined(separator: "\n")

        let prompt = """
        你是「Behavioral Scientist + Recovery Coach」。
        你要處理 STEP 5 — RECOVERY ENGINE（中斷保護）。
        \(previousErrorBlock)

        【硬性禁止】
        - 禁止輸出 cadence 字：每天、每日、天天。
        - 禁止 KPI/連續天數。

        【輸入】
        goal（sanitize 後）：\(safeGoal)
        identityForm：\(normalization.identityForm)
        masteryState：\(normalization.masteryState)

        PASS1 研究提示（失敗模式/阻力）：
        阻力機制：
        \(fr)
        失敗模式：
        \(fm)

        【輸出】
        只輸出 JSON：
        {
          "step": 5,
          "recoverySystem": {
            "microRecovery": "最小能力維持行為",
            "identityProtection": "避免身份崩塌機制",
            "resetRule": "中斷後如何重新回到能力軌道"
          }
        }

        【要求】
        - microRecovery：一個低摩擦、可立即做的維持行為（不是口號）
        - identityProtection：一句話/一個機制，避免把中斷解讀成『我不行』
        - resetRule：明確規則：中斷後下一次怎樣回到最小版本（不追 KPI、不補做）

        只回傳 JSON。
        """

        struct Envelope: Decodable {
            let step: Int
            let recoverySystem: RecoverySystem
        }

        let requestBody: [String: Any] = [
            "model": model,
            "input": [
                ["role": "system", "content": "You are a helpful assistant. Respond in JSON only."],
                ["role": "user", "content": prompt]
            ],
            "text": ["format": ["type": "json_object"]],
            "max_output_tokens": 600
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: [])
        request.timeoutInterval = 120

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OpenAIError.network("無法取得回應") }
        if !(200...299).contains(http.statusCode) {
            let message = String(data: data, encoding: .utf8) ?? "狀態碼 \(http.statusCode)"
            throw OpenAIError.server(message)
        }
        let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        if let error = decoded.error { throw OpenAIError.server(error.message) }
        let text = decoded.outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let jsonData = text.data(using: .utf8) else { throw OpenAIError.parse("STEP5 回應內容為空") }

        let env: Envelope
        do {
            env = try JSONDecoder().decode(Envelope.self, from: jsonData)
        } catch {
            let preview = text.prefix(400)
            throw OpenAIError.parse("STEP5 JSON 解析失敗：\(error.localizedDescription)\npreview: \(preview)")
        }
        if env.step != 5 { throw OpenAIError.parse("STEP5 step 必須為 5") }

        let banned = ["每天", "每日", "天天"]
        let allText = "\(env.recoverySystem.microRecovery)\n\(env.recoverySystem.identityProtection)\n\(env.recoverySystem.resetRule)"
        for w in banned where allText.contains(w) { throw OpenAIError.parse("STEP5 輸出包含禁字：\(w)") }

        func nonEmpty(_ s: String) -> Bool { !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !nonEmpty(env.recoverySystem.microRecovery) { throw OpenAIError.parse("STEP5 microRecovery 不可為空") }
        if !nonEmpty(env.recoverySystem.identityProtection) { throw OpenAIError.parse("STEP5 identityProtection 不可為空") }
        if !nonEmpty(env.recoverySystem.resetRule) { throw OpenAIError.parse("STEP5 resetRule 不可為空") }

        return env.recoverySystem
    }

    func generateHabitGuide(goal: String) async throws -> HabitGuide {
        // Lightweight pipeline (PASS A → PASS B)
        // PASS A: capability evolution + steps (no bingo)
        // PASS B: compile micro bingo tasks strictly from PASS A steps

        let bannedCadence = ["每天", "每日", "天天", "打卡"]
        func sanitizeGoal(_ g: String) -> String {
            var s = g
            for w in bannedCadence {
                s = s.replacingOccurrences(of: w, with: "")
            }
            return s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let safeGoal = sanitizeGoal(goal)
        let promptGoal = safeGoal.isEmpty ? goal : safeGoal

        func requestJSON<T>(label: String, maxOutputTokens: Int, prompt: String, parse: (Data) throws -> T, emptyError: String, parseErrorPrefix: String) async throws -> T {
            let requestBody: [String: Any] = [
                "model": model,
                "input": [
                    ["role": "system", "content": "You are a helpful assistant. Respond in JSON only."],
                    ["role": "user", "content": prompt]
                ],
                "text": ["format": ["type": "json_object"]],
                "max_output_tokens": maxOutputTokens
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
                if let urlError = error as? URLError,
                   urlError.code == .networkConnectionLost || urlError.code == .timedOut {
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    (data, response) = try await URLSession.shared.data(for: request)
                } else {
                    throw error
                }
            }

            guard let http = response as? HTTPURLResponse else { throw OpenAIError.network("無法取得回應") }
            if !(200...299).contains(http.statusCode) {
                let message = String(data: data, encoding: .utf8) ?? "狀態碼 \(http.statusCode)"
                throw OpenAIError.server(message)
            }

            let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
            if let error = decoded.error { throw OpenAIError.server(error.message) }

            if let u = decoded.usage {
                print("[OpenAI][\(label)] usage input=\(u.input_tokens) output=\(u.output_tokens) total=\(u.total_tokens)")
                OpenAIStore.setLastUsage(label: label, input: u.input_tokens, output: u.output_tokens, total: u.total_tokens)
            } else {
                print("[OpenAI][\(label)] usage (missing)")
            }

            let text = decoded.outputText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, let jsonData = text.data(using: .utf8) else { throw OpenAIError.parse(emptyError) }

            do {
                return try parse(jsonData)
            } catch {
                let preview = text.prefix(500)
                throw OpenAIError.parse("\(parseErrorPrefix)：\(error.localizedDescription)\\npreview: \(preview)")
            }
        }

        // PASS A schema
        struct PassAStep: Decodable {
            let stepId: String
            let title: String
            let capabilityBuilt: String
            let ifSkipped: String
            let smallWinMechanism: String
            let fallback: String
            let durationSec: Int
            let category: String
        }
        struct PassAStage: Decodable {
            let stage: Int
            let stageName: String
            let stageRationale: String
            let steps: [PassAStep]
        }
        struct PassAResponse: Decodable {
            let capabilityEssence: String
            let capabilityLayers: [String]
            let capabilityThresholds: [String]
            let stages: [PassAStage]
        }

        func validateNoBannedText(_ text: String) throws {
            let banned = bannedCadence + [
                "連續", "第X週", "第X天", "第一天", "第二天", "3→10→30",
                "培養觸發點", "建立儀式", "克服阻力", "開始行動", "嘗試一下", "做一個很小的步驟"
            ]
            for w in banned where text.contains(w) {
                throw OpenAIError.parse("輸出包含禁詞：\(w)")
            }
        }

        func validatePassA(_ a: PassAResponse) throws {
            try validateNoBannedText([a.capabilityEssence, a.capabilityLayers.joined(separator: "\\n"), a.capabilityThresholds.joined(separator: "\\n")].joined(separator: "\\n"))
            if a.capabilityEssence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw OpenAIError.parse("PASS A capabilityEssence 不可為空")
            }
            if a.capabilityLayers.count < 3 {
                throw OpenAIError.parse("PASS A capabilityLayers 太少")
            }
            if a.capabilityThresholds.count < 2 {
                throw OpenAIError.parse("PASS A capabilityThresholds 太少")
            }
            if a.stages.isEmpty {
                throw OpenAIError.parse("PASS A stages 不可為空")
            }

            let idx = a.stages.map { $0.stage }
            if Set(idx).count != idx.count {
                throw OpenAIError.parse("PASS A stage 重複")
            }
            if Set(idx) != Set([0, 1, 2, 3, 4]) {
                throw OpenAIError.parse("PASS A stages 必須包含 stage=0..4")
            }

            for st in a.stages {
                if st.steps.isEmpty {
                    throw OpenAIError.parse("PASS A stage \(st.stage) steps 不可為空")
                }
            }

            let totalSteps = a.stages.reduce(0) { $0 + $1.steps.count }
            if totalSteps < 5 || totalSteps > 12 {
                throw OpenAIError.parse("PASS A 總步驟數不合理（期望 5–12），目前：\(totalSteps)")
            }

            for st in a.stages {
                try validateNoBannedText(st.stageRationale)
                if st.steps.isEmpty {
                    throw OpenAIError.parse("PASS A stage \(st.stage) steps 不可為空")
                }
                for s in st.steps {
                    try validateNoBannedText([s.stepId, s.title, s.capabilityBuilt, s.ifSkipped, s.smallWinMechanism, s.fallback, s.category].joined(separator: "\\n"))
                    if s.stepId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        throw OpenAIError.parse("PASS A stepId 不可為空")
                    }
                    if s.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        throw OpenAIError.parse("PASS A step \(s.stepId) title 不可為空")
                    }
                    if !(30...600).contains(s.durationSec) {
                        throw OpenAIError.parse("PASS A step \(s.stepId) durationSec 必須為 30–600（目前：\(s.durationSec)）")
                    }
                }
            }
        }

        let passAPrompt = """
用戶目標：\(promptGoal)
你是「能力轉變設計師」。請從「正面心理學」與「原子習慣」角度，先建立此習慣的能力演化模型，再由能力模型自然推導行為。

⚠️ 不要先寫步驟，先完成能力模型。
⚠️ 不要使用時間遞增模板（例如 3→10→30、第一天第二天、第X週、第X天、連續X天）。
⚠️ 不要給泛用健康網站建議。
⚠️ 不要為湊數生成內容。
⚠️ 禁止出現：每天、每日、天天、打卡。
⚠️ 禁止抽象步驟名或口號（例如：培養觸發點、建立儀式、克服阻力、開始行動、嘗試一下、做一個很小的步驟）。

【第一層：能力本質】
1) capabilityEssence：一句話說明核心能力本質（不是行為表面）
2) capabilityLayers：描述能力從「未形成 → 可啟動 → 可穩定 → 可回復 → 可內化」的層級演變（不按時間，只按能力深度）。
- 每一層用 1 句描述「能力狀態 + 可觀察表現（不要 KPI/次數/時間）」
- 請保持精煉，不要長篇解釋

【第二層：能力壓縮】
將上述能力層級壓縮為「必要能力門檻」列表 capabilityThresholds。
- 若某層級不需要獨立門檻，請合併
- 每個門檻用 1 句描述「達到門檻代表什麼能力已具備」（不要 KPI/時間）

【第三層：行為生成】
根據 capabilityThresholds 自然生成具體行為 steps：
規則：
- 步驟數量由能力需求自然決定
- 每個步驟必須是「單一可做動作」（一個完整動作循環，避免多動作串在同一句）
- 每個步驟必須包含：capabilityBuilt、ifSkipped、smallWinMechanism、fallback、durationSec(30–600整數)、category(環境/微決策/身體/語言/社交擇一)
- 每個步驟 title 必須具體可做；不可是概念口號

【理論引用（要短、要落地）】
- 在 stageRationale 中用 1–2 句短句引用：
  - 正面心理學：PERMA / 自我效能 / 成長型心態（至少提到其中 1 個）
  - 原子習慣：cue / identity / small wins（至少提到其中 1 個）

【輸出 JSON】只回傳 JSON，不要任何解釋文字：
{
  "capabilityEssence": "...",
  "capabilityLayers": ["未形成：...","可啟動：...","可穩定：...","可回復：...","可內化：..."],
  "capabilityThresholds": ["門檻1：...","門檻2：..."],
  "stages": [
    {
      "stage": 0,
      "stageName": "種子",
      "stageRationale": "1–2句：引用 PERMA/自我效能/成長型心態 + cue/identity/small wins（短句即可）",
      "steps": [
        {
          "stepId": "S1",
          "title": "具體可做動作（單一動作循環）",
          "capabilityBuilt": "對應門檻X（用 capabilityThresholds 的詞）",
          "ifSkipped": "具體會卡住的點",
          "smallWinMechanism": "一句話 small win → 自我效能",
          "fallback": "更低阻力版本（仍然是動作）",
          "durationSec": 45,
          "category": "環境/微決策/身體/語言/社交"
        }
      ]
    },
    {"stage":1,"stageName":"發芽","stageRationale":"...","steps":[{"stepId":"P1","title":"...","capabilityBuilt":"...","ifSkipped":"...","smallWinMechanism":"...","fallback":"...","durationSec":45,"category":"..."}]},
    {"stage":2,"stageName":"長葉","stageRationale":"...","steps":[{"stepId":"L1","title":"...","capabilityBuilt":"...","ifSkipped":"...","smallWinMechanism":"...","fallback":"...","durationSec":45,"category":"..."}]},
    {"stage":3,"stageName":"開花","stageRationale":"...","steps":[{"stepId":"B1","title":"...","capabilityBuilt":"...","ifSkipped":"...","smallWinMechanism":"...","fallback":"...","durationSec":45,"category":"..."}]},
    {"stage":4,"stageName":"扎根","stageRationale":"...","steps":[{"stepId":"R1","title":"...","capabilityBuilt":"...","ifSkipped":"...","smallWinMechanism":"...","fallback":"...","durationSec":45,"category":"..."}]}
  ]
}

硬規則：stages 必須包含 stage=0,1,2,3,4 且每個 stage 至少 1 個 step；總 step 數至少 5。
"""

        var passA: PassAResponse
        do {
            passA = try await requestJSON(label: "PASS A", maxOutputTokens: 2000, prompt: passAPrompt, parse: { data in
                try JSONDecoder().decode(PassAResponse.self, from: data)
            }, emptyError: "PASS A 回應內容為空", parseErrorPrefix: "PASS A JSON 解析失敗")
            try validatePassA(passA)
        } catch {
            // One retry with error feedback (keep it short)
            let errText = (error as? OpenAIError).map(String.init(describing:)) ?? error.localizedDescription
            let retryPrompt = """
你上一份 PASS A 輸出未通過驗證：\(errText)
請只修正錯誤點，重新輸出完整 JSON（不要額外文字）。
\(passAPrompt)
"""
            passA = try await requestJSON(label: "PASS A (retry)", maxOutputTokens: 2000, prompt: retryPrompt, parse: { data in
                try JSONDecoder().decode(PassAResponse.self, from: data)
            }, emptyError: "PASS A 回應內容為空", parseErrorPrefix: "PASS A JSON 解析失敗")
            try validatePassA(passA)
        }

        // PASS B schema (adds bingoTasks)
        struct PassBTask: Decodable {
            let taskId: String?
            let mapsToStep: String?
            let text: String
            let durationSec: Int?
            let observable: String?
            let successProbability: Double?
        }
        struct PassBBingo: Decodable {
            let tasks: [PassBTask]
        }
        struct PassBStep: Decodable {
            let stepId: String
            let title: String
            let fallback: String
            let durationSec: Int
            let category: String
            let bingoTasks: PassBBingo
        }
        struct PassBStage: Decodable {
            let stage: Int
            let stageName: String
            let stageRationale: String
            let steps: [PassBStep]
        }
        struct PassBResponse: Decodable {
            let stages: [PassBStage]
        }

        func validatePassB(_ b: PassBResponse) throws {
            if b.stages.isEmpty { throw OpenAIError.parse("PASS B stages 不可為空") }
            for st in b.stages {
                try validateNoBannedText(st.stageRationale)
                if st.steps.isEmpty { throw OpenAIError.parse("PASS B stage \(st.stage) steps 不可為空") }
                for s in st.steps {
                    try validateNoBannedText([s.stepId, s.title, s.fallback, s.category].joined(separator: "\\n"))
                    if !(30...600).contains(s.durationSec) { throw OpenAIError.parse("PASS B step \(s.stepId) durationSec 必須為 30–600") }
                    if s.bingoTasks.tasks.isEmpty { throw OpenAIError.parse("PASS B step \(s.stepId) bingoTasks 不可為空") }
                    for t in s.bingoTasks.tasks {
                        // Do NOT hard-lock bingo task duration. We only require the task itself to be a concrete, immediate action.
                        try validateNoBannedText(t.text)
                        if let dur = t.durationSec {
                            if dur <= 0 { throw OpenAIError.parse("PASS B task durationSec 必須為正數（step \(s.stepId)）") }
                            if dur > 1800 { throw OpenAIError.parse("PASS B task durationSec 過長（>1800 秒）（step \(s.stepId)）") }
                        }
                    }
                }
            }
        }

        // Provide PASS A steps as a compact list
        let passAStepsText: String = passA.stages
            .sorted(by: { $0.stage < $1.stage })
            .flatMap { st in
                st.steps.map { s in
                    "- stage \(st.stage) \(st.stageName) \(s.stepId): \(s.title)｜fallback=\(s.fallback)｜dur=\(s.durationSec)s｜cat=\(s.category)"
                }
            }
            .joined(separator: "\\n")

        let passBPrompt = """
用戶目標：\(promptGoal)
你是「Bingo 任務拆解師」。請只根據 PASS A 既 steps，為每個 step 拆出 micro bingoTasks。

⚠️ 禁止出現：每天、每日、天天、打卡。
⚠️ 禁止時間遞增模板、連續X天。
⚠️ bingoTasks 必須是可立即做的細動作（一個完整動作循環）。
⚠️ durationSec 不要鎖死（可依用戶心情/動機/昨天難度調整）；若有填寫，請給一個合理估計秒數。

【PASS A steps（不可改動 stepId/title/fallback/durationSec/category，只可補 bingoTasks）】
\(passAStepsText)

【輸出 JSON】只回傳 JSON：
{
  "stages": [
    {
      "stage": 0,
      "stageName": "...",
      "stageRationale": "1–2句（引用 PERMA/自我效能/成長型心態 + cue/identity/small wins；短句即可）",
      "steps": [
        {
          "stepId": "S1",
          "title": "...",
          "fallback": "...",
          "durationSec": 45,
          "category": "...",
          "bingoTasks": {
            "tasks": [
              {"taskId":"S1-T1","mapsToStep":"S1","text":"...","durationSec":45,"observable":"...","successProbability":0.75}
            ]
          }
        }
      ]
    }
  ]
}
"""

        var passB: PassBResponse
        do {
            passB = try await requestJSON(label: "PASS B", maxOutputTokens: 2200, prompt: passBPrompt, parse: { data in
                try JSONDecoder().decode(PassBResponse.self, from: data)
            }, emptyError: "PASS B 回應內容為空", parseErrorPrefix: "PASS B JSON 解析失敗")
            try validatePassB(passB)
        } catch {
            let errText = (error as? OpenAIError).map(String.init(describing:)) ?? error.localizedDescription
            let retryPrompt = """
你上一份 PASS B 輸出未通過驗證：\(errText)
請只修正錯誤點，重新輸出完整 JSON（不要額外文字）。
\(passBPrompt)
"""
            passB = try await requestJSON(label: "PASS B (retry)", maxOutputTokens: 2200, prompt: retryPrompt, parse: { data in
                try JSONDecoder().decode(PassBResponse.self, from: data)
            }, emptyError: "PASS B 回應內容為空", parseErrorPrefix: "PASS B JSON 解析失敗")
            try validatePassB(passB)
        }

        // Build HabitGuide (older deep pipeline fields are nil; Habit Map is still fully functional)
        let stages: [HabitStageGuide] = passB.stages
            .sorted(by: { $0.stage < $1.stage })
            .map { st in
                let steps: [HabitGuideStep] = st.steps.map { s in
                    let sid = s.stepId.trimmingCharacters(in: .whitespacesAndNewlines)
                    let title = s.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    let fallback = s.fallback.trimmingCharacters(in: .whitespacesAndNewlines)
                    let durationText = "\(s.durationSec) 秒"
                    let category = s.category.trimmingCharacters(in: .whitespacesAndNewlines)

                    let bingoTaskObjs: [BingoTask] = s.bingoTasks.tasks.enumerated().map { idx, t in
                        let taskId = (t.taskId ?? "\(sid)-T\(idx + 1)").trimmingCharacters(in: .whitespacesAndNewlines)
                        let mapsTo = (t.mapsToStep ?? sid).trimmingCharacters(in: .whitespacesAndNewlines)
                        let text = t.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        let durRaw = t.durationSec ?? 45
                        let dur = max(5, min(1800, durRaw))
                        let observable = (t.observable ?? "完成：\(text)").trimmingCharacters(in: .whitespacesAndNewlines)
                        let sp = min(0.99, max(0.01, t.successProbability ?? 0.75))
                        return BingoTask(taskId: taskId, mapsToStep: mapsTo, derivedFromInterventionIds: [], text: text, durationSec: dur, observable: observable, successProbability: sp)
                    }

                    return HabitGuideStep(
                        id: UUID(),
                        stepId: sid,
                        derivedFromInterventionIds: [],
                        behaviorRef: nil,
                        capabilityRef: nil,
                        leverageRef: nil,
                        title: title,
                        duration: durationText,
                        fallback: fallback,
                        category: category,
                        requiredBingoCount: 2,
                        completedBingoCount: 0,
                        isCompleted: false,
                        bingoTasks: bingoTaskObjs
                    )
                }
                return HabitStageGuide(stage: st.stage, steps: steps)
            }

        return HabitGuide(
            goal: goal,
            goalNormalization: nil,
            skillModel: nil,
            capabilityStages: nil,
            habitArchitecture: nil,
            reinforcementUnits: nil,
            recoverySystem: nil,
            researchReport: nil,
            masteryDefinition: passA.capabilityEssence.trimmingCharacters(in: .whitespacesAndNewlines),
            frictions: [],
            methodRoute: [],
            stages: stages,
            updatedAt: Date()
        )
    }



    private static func validateHabitGuideResponse(
        goal: String,
        researchReport: HabitResearchReport?,
        skillModel: SkillModelReport?,
        habitArchitecture: HabitArchitecture?,
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

        // PASS2 should compile from STEP3 behaviors + STEP1 skill model.
        let capabilityIds: Set<String> = Set(skillModel?.requiredCapabilities.map { $0.capabilityId } ?? [])
        let leverageIds: Set<String> = Set(skillModel?.leveragePoints.map { $0.leverageId } ?? [])
        let behaviorById: [String: HabitBehavior] = {
            guard let habitArchitecture else { return [:] }
            var map: [String: HabitBehavior] = [:]
            for st in habitArchitecture.stages {
                for b in st.behaviors {
                    map[b.behaviorId] = b
                }
            }
            return map
        }()

        for s in stages {
            if s.steps.count < 2 {
                throw OpenAIError.parse("stage \(s.stage) steps 至少 2 個")
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

                // Enforce compilation linkage to STEP3 behaviors when available.
                if !behaviorById.isEmpty {
                    let bRef = (step.behaviorRef ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if bRef.isEmpty {
                        throw OpenAIError.parse("step \(sidRaw) 缺少 behaviorRef（必須由 STEP3 behaviors 編譯）")
                    }
                    guard let b = behaviorById[bRef] else {
                        throw OpenAIError.parse("step \(sidRaw) behaviorRef 不存在：\(bRef)")
                    }

                    let capRef = (step.capabilityRef ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let levRef = (step.leverageRef ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if capRef.isEmpty || levRef.isEmpty {
                        throw OpenAIError.parse("step \(sidRaw) 缺少 capabilityRef/leverageRef")
                    }
                    if !capabilityIds.isEmpty, !capabilityIds.contains(capRef) {
                        throw OpenAIError.parse("step \(sidRaw) capabilityRef 不存在：\(capRef)")
                    }
                    if !leverageIds.isEmpty, !leverageIds.contains(levRef) {
                        throw OpenAIError.parse("step \(sidRaw) leverageRef 不存在：\(levRef)")
                    }
                    if capRef != b.capabilityRef {
                        throw OpenAIError.parse("step \(sidRaw) capabilityRef 必須與 behavior \(bRef) 一致（期望 \(b.capabilityRef)，得到 \(capRef)）")
                    }
                    if levRef != b.leverageRef {
                        throw OpenAIError.parse("step \(sidRaw) leverageRef 必須與 behavior \(bRef) 一致（期望 \(b.leverageRef)，得到 \(levRef)）")
                    }
                }

                if s.stage == 4 {
                    stage4CombinedText += "\n" + title + " " + duration + " " + fallback
                    if let tasks = step.bingoTasks?.tasks {
                        stage4CombinedText += " " + tasks.map { $0.text }.joined(separator: " ")
                    }
                }

                let tasksField = step.bingoTasks?.tasks ?? []
                let tasks = tasksField.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                if tasks.count < 2 {
                    throw OpenAIError.parse("step \(sidRaw) bingoTasks 至少 2 個")
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

    private enum CodingKeys: String, CodingKey {
        case tasks
    }

    init(from decoder: Decoder) throws {
        // New shape: { "tasks": [ ... ] }
        if let keyed = try? decoder.container(keyedBy: CodingKeys.self),
           let obj = try? keyed.decode([BingoTaskResponse].self, forKey: .tasks) {
            self.tasks = obj
            return
        }

        // Legacy shapes: [ { ... } ] or ["..."]
        let container = try decoder.singleValueContainer()
        if let objTasks = try? container.decode([BingoTaskResponse].self) {
            self.tasks = objTasks
            return
        }
        let legacy = (try? container.decode([String].self)) ?? []
        self.tasks = legacy.enumerated().map { _, t in
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

    /// STEP3 compilation traceability (PASS2 should compile from STEP3 behaviors)
    var behaviorRef: String?
    var capabilityRef: String?
    var leverageRef: String?

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

    struct Usage: Decodable {
        let input_tokens: Int
        let output_tokens: Int
        let total_tokens: Int
    }

    let output: [OutputItem]?
    let error: APIError?
    let usage: Usage?

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
