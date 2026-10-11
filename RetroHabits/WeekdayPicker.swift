import SwiftUI

/// Seven round day toggles (S M T W T F S). Selection uses Calendar weekdays, 1 = Sunday.
struct WeekdayPicker: View {
    @Binding var selection: Set<Int>

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { day in
                let isOn = selection.contains(day)
                Button {
                    if isOn { selection.remove(day) } else { selection.insert(day) }
                } label: {
                    Text(Calendar.current.veryShortWeekdaySymbols[day - 1])
                        .font(.subheadline.bold())
                        .foregroundStyle(isOn ? .white : Palette.ink)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Circle().fill(isOn ? Palette.blue : Palette.fill))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Calendar.current.weekdaySymbols[day - 1])
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}
