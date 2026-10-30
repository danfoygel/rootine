import SwiftUI

/// Color swatches and a symbol grid for an item's icon.
struct AppearancePicker: View {
    @Binding var symbolName: String
    @Binding var colorName: String

    private var tint: Color {
        ItemColor.named(colorName).color
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 12) {
                    ForEach(ItemColor.allCases) { color in
                        Button {
                            colorName = color.rawValue
                        } label: {
                            Circle()
                                .fill(color.color)
                                .frame(width: 34, height: 34)
                                .overlay {
                                    if color.rawValue == colorName {
                                        Image(systemName: "checkmark")
                                            .font(.caption.bold())
                                            .foregroundStyle(.white)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(color.rawValue.capitalized)
                        .accessibilityAddTraits(color.rawValue == colorName ? .isSelected : [])
                    }
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                    ForEach(ItemSymbols.all, id: \.self) { symbol in
                        let isSelected = symbol == symbolName
                        Button {
                            symbolName = symbol
                        } label: {
                            Image(systemName: symbol)
                                .font(.title3)
                                .frame(width: 46, height: 46)
                                .foregroundStyle(isSelected ? .white : tint)
                                .background(isSelected ? tint : tint.opacity(0.12), in: .rect(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(symbol)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Icon")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A row of weekday toggles, in the locale's week order.
struct WeekdayPicker: View {
    @Binding var selection: Set<Int>

    private let calendar = Calendar.current

    var body: some View {
        let order = (0 ..< 7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
        HStack(spacing: 6) {
            ForEach(order, id: \.self) { weekday in
                let isOn = selection.contains(weekday)
                Button {
                    if isOn {
                        selection.remove(weekday)
                    } else {
                        selection.insert(weekday)
                    }
                } label: {
                    Text(calendar.veryShortWeekdaySymbols[weekday - 1])
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .foregroundStyle(isOn ? .white : .primary)
                        .background(isOn ? Color.accentColor : Color(.tertiarySystemFill), in: .circle)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(calendar.weekdaySymbols[weekday - 1])
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}
