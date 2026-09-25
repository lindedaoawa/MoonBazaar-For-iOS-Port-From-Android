import SwiftUI

/// 与 Android `ui/theme` 对应的配色。
///
/// Android 端优先使用 Material You 动态色，回退到固定的 Purple 系列；
/// iOS 没有动态取色能力，因此这里直接采用同一套回退色（Purple / PurpleGrey / Pink），
/// 并随系统深/浅色切换。
struct MoonColors {
    let primary: Color
    let secondary: Color
    let tertiary: Color
    let onPrimary: Color
    let outline: Color
    let error: Color
    let errorContainer: Color
    let onErrorContainer: Color
    let gain: Color
    let loss: Color
}

enum MoonTheme {
    static func of(_ scheme: ColorScheme) -> MoonColors {
        let dark = scheme == .dark
        return MoonColors(
            primary: hex(dark ? 0xD0BCFF : 0x6650A4),
            secondary: hex(dark ? 0xCCC2DC : 0x625B71),
            tertiary: hex(dark ? 0xEFB8C8 : 0x7D5260),
            onPrimary: dark ? hex(0x381E72) : .white,
            outline: dark ? hex(0x938F99) : hex(0x79747E),
            error: hex(dark ? 0xF2B8B5 : 0xB3261E),
            errorContainer: hex(dark ? 0x8C1D18 : 0xF9DEDC),
            onErrorContainer: hex(dark ? 0xF9DEDC : 0x410E0B),
            gain: hex(0x1B8A3A),
            loss: hex(0xC62828)
        )
    }

    static func hex(_ value: UInt32) -> Color {
        Color(
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0
        )
    }

    /// 首页 hero 渐变（primary → tertiary）。
    static func heroGradient(_ colors: MoonColors) -> LinearGradient {
        LinearGradient(colors: [colors.primary, colors.tertiary],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// 主题色的简写：`@Environment(\.colorScheme) var scheme; @Environment(\.moonColors) var c`
private struct MoonColorsKey: EnvironmentKey {
    static let defaultValue = MoonTheme.of(.light)
}

extension EnvironmentValues {
    var moonColors: MoonColors {
        get { self[MoonColorsKey.self] }
        set { self[MoonColorsKey.self] = newValue }
    }
}

/// 在根视图上注入当前深浅色对应的调色板。
struct MoonThemeRoot<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .environment(\.moonColors, MoonTheme.of(scheme))
            .tint(MoonTheme.of(scheme).primary)
    }
}