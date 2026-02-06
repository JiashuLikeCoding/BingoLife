//
//  Theme.swift
//  Life Bingo
//
//  Created by Jason Li on 2026-02-02.
//

import SwiftUI

enum ThemeKey: String, CaseIterable, Codable {
    case sage
    case clay
    case mist
    case ocean
    case ink

    var displayName: String {
        switch self {
        case .sage: return "森"
        case .clay: return "土"
        case .mist: return "霧"
        case .ocean: return "海"
        case .ink: return "墨"
        }
    }
}

struct ThemePalette {
    let backgroundTop: Color
    let backgroundBottom: Color
    let surface: Color
    let surfaceAlt: Color
    let accent: Color
    let accentSoft: Color
    let textPrimary: Color
    let textSecondary: Color
    let border: Color
    let shadow: Color
    let gold: Color

    static func palette(for key: ThemeKey) -> ThemePalette {
        switch key {
        case .sage:
            return ThemePalette(
                backgroundTop: Color(red: 0.97, green: 0.95, blue: 0.92),
                backgroundBottom: Color(red: 0.94, green: 0.92, blue: 0.89),
                surface: Color(red: 0.99, green: 0.97, blue: 0.95),
                surfaceAlt: Color(red: 0.95, green: 0.93, blue: 0.90),
                accent: Color(red: 0.36, green: 0.48, blue: 0.38),
                accentSoft: Color(red: 0.86, green: 0.88, blue: 0.83),
                textPrimary: Color(red: 0.21, green: 0.19, blue: 0.17),
                textSecondary: Color(red: 0.49, green: 0.45, blue: 0.41),
                border: Color.black.opacity(0.04),
                shadow: Color.black.opacity(0.02),
                gold: Color(red: 0.73, green: 0.66, blue: 0.52)
            )
        case .clay:
            return ThemePalette(
                backgroundTop: Color(red: 0.98, green: 0.95, blue: 0.93),
                backgroundBottom: Color(red: 0.95, green: 0.92, blue: 0.90),
                surface: Color(red: 1.00, green: 0.97, blue: 0.95),
                surfaceAlt: Color(red: 0.96, green: 0.93, blue: 0.91),
                accent: Color(red: 0.63, green: 0.43, blue: 0.33),
                accentSoft: Color(red: 0.90, green: 0.85, blue: 0.82),
                textPrimary: Color(red: 0.25, green: 0.20, blue: 0.18),
                textSecondary: Color(red: 0.52, green: 0.44, blue: 0.40),
                border: Color.black.opacity(0.04),
                shadow: Color.black.opacity(0.02),
                gold: Color(red: 0.76, green: 0.62, blue: 0.48)
            )
        case .mist:
            return ThemePalette(
                backgroundTop: Color(red: 0.96, green: 0.97, blue: 0.97),
                backgroundBottom: Color(red: 0.93, green: 0.95, blue: 0.95),
                surface: Color(red: 0.99, green: 0.99, blue: 0.99),
                surfaceAlt: Color(red: 0.94, green: 0.96, blue: 0.96),
                accent: Color(red: 0.36, green: 0.49, blue: 0.54),
                accentSoft: Color(red: 0.84, green: 0.90, blue: 0.91),
                textPrimary: Color(red: 0.20, green: 0.22, blue: 0.24),
                textSecondary: Color(red: 0.46, green: 0.50, blue: 0.52),
                border: Color.black.opacity(0.04),
                shadow: Color.black.opacity(0.02),
                gold: Color(red: 0.69, green: 0.69, blue: 0.68)
            )
        case .ocean:
            return ThemePalette(
                backgroundTop: Color(red: 0.95, green: 0.97, blue: 0.98),
                backgroundBottom: Color(red: 0.90, green: 0.94, blue: 0.96),
                surface: Color(red: 0.98, green: 0.99, blue: 1.00),
                surfaceAlt: Color(red: 0.92, green: 0.95, blue: 0.97),
                accent: Color(red: 0.20, green: 0.45, blue: 0.56),
                accentSoft: Color(red: 0.82, green: 0.89, blue: 0.92),
                textPrimary: Color(red: 0.18, green: 0.22, blue: 0.26),
                textSecondary: Color(red: 0.43, green: 0.49, blue: 0.54),
                border: Color.black.opacity(0.04),
                shadow: Color.black.opacity(0.02),
                gold: Color(red: 0.66, green: 0.70, blue: 0.72)
            )
        case .ink:
            return ThemePalette(
                backgroundTop: Color(red: 0.95, green: 0.95, blue: 0.95),
                backgroundBottom: Color(red: 0.92, green: 0.92, blue: 0.92),
                surface: Color(red: 0.98, green: 0.98, blue: 0.98),
                surfaceAlt: Color(red: 0.93, green: 0.93, blue: 0.93),
                accent: Color(red: 0.22, green: 0.27, blue: 0.33),
                accentSoft: Color(red: 0.86, green: 0.87, blue: 0.88),
                textPrimary: Color(red: 0.16, green: 0.18, blue: 0.20),
                textSecondary: Color(red: 0.44, green: 0.46, blue: 0.48),
                border: Color.black.opacity(0.04),
                shadow: Color.black.opacity(0.02),
                gold: Color(red: 0.66, green: 0.66, blue: 0.66)
            )
        }
    }
}

enum Theme {
    private static var palette = ThemePalette.palette(for: .sage)

    static func apply(_ key: ThemeKey) {
        palette = ThemePalette.palette(for: key)
    }

    static var backgroundTop: Color { palette.backgroundTop }
    static var backgroundBottom: Color { palette.backgroundBottom }
    static var surface: Color { palette.surface }
    static var surfaceAlt: Color { palette.surfaceAlt }
    static var accent: Color { palette.accent }
    static var accentSoft: Color { palette.accentSoft }
    static var textPrimary: Color { palette.textPrimary }
    static var textSecondary: Color { palette.textSecondary }
    static var border: Color { palette.border }
    static var shadow: Color { palette.shadow }
    static var gold: Color { palette.gold }

    enum Fonts {
        static func title(_ size: CGFloat = 0) -> Font {
            .system(.title)
        }

        static func headline(_ size: CGFloat = 0) -> Font {
            .system(.title3)
        }

        static func body(_ size: CGFloat = 0) -> Font {
            .system(.body)
        }

        static func caption(_ size: CGFloat = 0) -> Font {
            if size > 0 && size <= 11 {
                return .system(.caption2)
            }
            return .system(.footnote)
        }
    }
}

struct AppBackground<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.backgroundTop, Theme.backgroundBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            Circle()
                .fill(Theme.accentSoft.opacity(0.35))
                .frame(width: 320, height: 320)
                .blur(radius: 40)
                .offset(x: -140, y: -220)
            Circle()
                .fill(Theme.gold.opacity(0.20))
                .frame(width: 240, height: 240)
                .blur(radius: 30)
                .offset(x: 140, y: 260)
            content
        }
        .foregroundStyle(Theme.textPrimary)
    }
}

struct Card<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1)
            )
    }
}

struct Chip: View {
    let text: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(text)
        }
        .font(Theme.Fonts.caption(12))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Theme.surfaceAlt)
        .clipShape(Capsule())
    }
}

struct StatusBadgeView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 6) {
            badge(icon: "bitcoinsign.circle.fill", value: appState.coins)
            badge(icon: "ticket", value: appState.skipTickets)
        }
    }

    private func badge(icon: String, value: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text("\(value)")
        }
        .font(Theme.Fonts.caption(11))
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.surfaceAlt)
        .clipShape(Capsule())
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Fonts.body())
            .fontWeight(.semibold)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Theme.accent)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Fonts.body())
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Theme.surface)
            .foregroundStyle(Theme.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct FieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(Theme.Fonts.body())
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.surfaceAlt)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1)
            )
    }
}

extension View {
    func themedField() -> some View {
        modifier(FieldStyle())
    }
}
