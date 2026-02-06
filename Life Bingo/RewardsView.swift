//
//  RewardsView.swift
//  Life Bingo
//
//  Created by Jason Li on 2026-02-02.
//

import SwiftUI

struct RewardsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.appLanguage) private var appLanguage
    @State private var showAdd = false
    @State private var showSettings = false
    @State private var alertMessage: String?
    @State private var newTitle = ""
    @State private var newCost = 10

    var body: some View {
        NavigationStack {
            AppBackground {
                ScrollView {
                    VStack(spacing: 18) {
                        Card {
                            VStack(alignment: .leading, spacing: 12) {
                                    Text(L10n.t("想要獎勵自己什麼", appLanguage))
                                        .font(Theme.Fonts.caption())
                                        .foregroundStyle(Theme.textSecondary)
                                if showAdd {
                                    TextField(L10n.t("想獎勵自己什麼", appLanguage), text: $newTitle)
                                        .themedField()
                                    Stepper(value: $newCost, in: 1...500) {
                                        HStack {
                                            Text(L10n.t("所需 coin", appLanguage))
                                                .font(Theme.Fonts.caption())
                                                .foregroundStyle(Theme.textSecondary)
                                            Spacer()
                                            Text("\(newCost)")
                                                .font(Theme.Fonts.body())
                                                .fontWeight(.semibold)
                                        }
                                    }
                                    .tint(Theme.accent)
                                    HStack(spacing: 8) {
                                        Button(L10n.t("保存", appLanguage)) {
                                            let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                                            guard !trimmed.isEmpty else { return }
                                            appState.addReward(title: trimmed, detail: "", cost: newCost, category: .purchase)
                                            newTitle = ""
                                            newCost = 10
                                            showAdd = false
                                        }
                                        .buttonStyle(PrimaryButtonStyle())
                                        Button(L10n.t("取消", appLanguage)) {
                                            newTitle = ""
                                            newCost = 10
                                            showAdd = false
                                        }
                                        .buttonStyle(SecondaryButtonStyle())
                                    }
                                } else {
                                    Button {
                                        showAdd = true
                                    } label: {
                                        Label(L10n.t("獎勵自己", appLanguage), systemImage: "plus")
                                    }
                                    .buttonStyle(PrimaryButtonStyle())
                                }
                            }
                        }
                        .overlay(alignment: .topTrailing) {
                            StatusBadgeView()
                                .padding(10)
                        }

                        Card {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(L10n.t("可兌換", appLanguage))
                                    .font(Theme.Fonts.caption())
                                    .foregroundStyle(Theme.textSecondary)
                                if activeItems.isEmpty {
                                    EmptyStatePanel(
                                        systemImage: "gift",
                                        title: L10n.t("還沒有獎勵", appLanguage),
                                        message: L10n.t("新增一個你想兌換的獎勵。", appLanguage)
                                    )
                                } else {
                                    ForEach(activeItems) { item in
                                        RewardRow(item: item, canRedeem: appState.coins >= item.cost) {
                                            if let error = appState.redeemReward(item) {
                                                alertMessage = error
                                            } else {
                                                alertMessage = L10n.t("兌換成功", appLanguage)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Card {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(L10n.t("已兌換", appLanguage))
                                    .font(Theme.Fonts.caption())
                                    .foregroundStyle(Theme.textSecondary)
                                if redeemedItems.isEmpty {
                                    EmptyStatePanel(
                                        systemImage: "checkmark.seal",
                                        title: L10n.t("還沒有兌換紀錄", appLanguage),
                                        message: L10n.t("完成第一個兌換目標吧。", appLanguage)
                                    )
                                } else {
                                    ForEach(redeemedItems) { item in
                                        RewardRow(item: item, canRedeem: false, onRedeem: nil)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle(L10n.t("兌換", appLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .alert(L10n.t("提示", appLanguage), isPresented: Binding(get: {
            alertMessage != nil
        }, set: { _ in
            alertMessage = nil
        })) {
            Button(L10n.t("知道了", appLanguage)) {
                alertMessage = nil
            }
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private var activeItems: [RewardItem] {
        appState.rewardItems.filter { !$0.isRedeemed }
    }

    private var redeemedItems: [RewardItem] {
        appState.rewardItems.filter { $0.isRedeemed }
    }
}

struct RewardRow: View {
    let item: RewardItem
    let canRedeem: Bool
    var onRedeem: (() -> Void)?
    @Environment(\.appLanguage) private var appLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title)
                        .font(Theme.Fonts.body())
                        .fontWeight(.semibold)
                    if !item.detail.isEmpty {
                        Text(item.detail)
                            .font(Theme.Fonts.caption())
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text("\(item.cost) coin")
                        .font(Theme.Fonts.body())
                        .fontWeight(.semibold)
                    if item.isRedeemed, let date = item.redeemedAt {
                        Text(DateKey.string(from: date))
                            .font(Theme.Fonts.caption())
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }

            if let onRedeem {
                if canRedeem {
                    Button(L10n.t("兌換", appLanguage)) {
                        onRedeem()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                } else {
                    Button(L10n.t("coin 不足", appLanguage)) {}
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(true)
                }
            } else if item.isRedeemed {
                Text(L10n.t("已兌換", appLanguage))
                    .font(Theme.Fonts.caption())
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(12)
        .background(Theme.surfaceAlt)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
