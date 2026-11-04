import SwiftUI

/// A strip of the last month's days to pick from: a dot under the days that have something, today ringed, the chosen day filled.
struct MomentsDayStrip: View {
    let days: [String]
    let withData: Set<String>
    let today: String
    @Binding var selected: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: Spacing.xs) {
                    ForEach(days, id: \.self) { day in cell(day).id(day) }
                }
                .padding(.horizontal, Spacing.xl)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -Spacing.xl)   // runs to the screen's edges while the page keeps its margins
            .onAppear { proxy.scrollTo(selected, anchor: .center) }
            .onChange(of: selected) { _, day in withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { proxy.scrollTo(day, anchor: .center) } }
        }
    }

    private func cell(_ day: String) -> some View {
        let date = DayID.date(of: day) ?? Date()
        let isSelected = day == selected
        return Button { selected = day } label: {
            VStack(spacing: 4) {
                Text(date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(isSelected ? Palette.teal : Palette.textSecondary)
                Text(date.formatted(.dateTime.day()))
                    .font(.system(.callout, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? Palette.background : (withData.contains(day) ? Palette.textPrimary : Palette.textTertiary))
                    .frame(width: 38, height: 38)
                    .background(isSelected ? Palette.teal : Color.clear, in: Circle())
                    .overlay { if day == today && !isSelected { Circle().strokeBorder(Palette.teal.opacity(0.7), lineWidth: 1.5) } }
                Circle().fill(withData.contains(day) ? Palette.teal : Color.clear).frame(width: 4, height: 4)
            }
            .frame(width: 44, height: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(EchoPressStyle())
        .accessibilityLabel("\(DayID.longLabel(day))\(withData.contains(day) ? "" : ", nothing heard")")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
