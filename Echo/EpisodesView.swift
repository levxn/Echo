import SwiftUI

/// The day as a vertical timeline of conversations.
struct EpisodesSection: View {
    let episodes: [Episode]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            SectionHeader("Your day", meta: "\(episodes.count) conversation\(episodes.count == 1 ? "" : "s")")
            VStack(spacing: Spacing.md) {
                ForEach(Array(episodes.enumerated()), id: \.element.id) { i, episode in
                    EpisodeRow(episode: episode, isLast: i == episodes.count - 1)
                }
            }
        }
    }
}

private struct EpisodeRow: View {
    let episode: Episode
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            VStack(spacing: 0) {
                Circle()
                    .fill(Palette.accentGradient)
                    .frame(width: 12, height: 12)
                    .shadow(color: Palette.teal.opacity(0.6), radius: 6)
                    .padding(.top, 24)
                if !isLast {
                    Capsule()
                        .fill(LinearGradient(colors: [Palette.teal.opacity(0.5), Palette.blue.opacity(0.1)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 12)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .firstTextBaseline) {
                    Text(episode.startLabel)
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Palette.textPrimary)
                    Text(episode.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Palette.textSecondary)
                    Spacer(minLength: 0)
                }
                Text(episode.gist)
                    .font(.subheadline)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                FlowLayout {
                    ForEach(episode.keywords, id: \.self) { Chip(text: $0) }
                }
                Text("\(episode.chunks.count) moments · about \(episode.minutes) min")
                    .font(.caption)
                    .foregroundStyle(Palette.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .echoCard(radius: Radius.card)
            .accessibilityElement(children: .combine)
        }
    }
}
