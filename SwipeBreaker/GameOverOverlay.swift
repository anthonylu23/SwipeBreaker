import SwiftUI

struct GameOverOverlay: View {
    let score: Int
    let best: Int
    let turn: Int
    let palette: Theme.Palette
    let onRestart: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            palette.background
                .opacity(0.35)
                .ignoresSafeArea()
                .allowsHitTesting(true)

            VStack(spacing: 18) {
                Text("GAME OVER")
                    .font(Theme.Fonts.mono(26, weight: .bold))
                    .foregroundStyle(palette.destructive)
                    .tracking(3)

                VStack(spacing: 4) {
                    Text("SCORE")
                        .font(Theme.Fonts.mono(11, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                        .tracking(2)
                    Text("\(score)")
                        .font(Theme.Fonts.mono(58, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .contentTransition(.numericText())
                }

                HStack(spacing: 36) {
                    stat("BEST", "\(best)")
                    stat("TURN", "\(turn)")
                }
                .padding(.top, 4)

                Button(action: onRestart) {
                    Text("TAP TO PLAY AGAIN")
                        .font(Theme.Fonts.mono(13, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(palette.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }
                .glassEffect(
                    .regular.tint(palette.primary.opacity(0.18)).interactive(),
                    in: .rect(cornerRadius: Theme.radiusSm)
                )
                .padding(.top, 8)
            }
            .padding(28)
            .frame(width: 320)
            .glassEffect(in: .rect(cornerRadius: Theme.radius))
            .shadow(color: palette.glow.opacity(0.25), radius: 30, y: 12)
            .scaleEffect(appeared ? 1 : 0.94)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.45).delay(0.15)) {
                appeared = true
            }
        }
    }

    @ViewBuilder
    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(Theme.Fonts.mono(10, weight: .medium))
                .foregroundStyle(palette.textSecondary)
                .tracking(1.5)
            Text(value)
                .font(Theme.Fonts.mono(18, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
        }
    }
}
