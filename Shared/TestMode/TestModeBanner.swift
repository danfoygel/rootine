import SwiftUI

/// The bar shown on both apps while test mode is on, so test data is never mistaken for real data.
struct TestModeBanner: View {
    let scenario: Scenario
    var action: (() -> Void)?

    var body: some View {
        Button {
            action?()
        } label: {
            Label("TEST DATA · \(scenario.title)", systemImage: "flask")
                .font(.caption.bold())
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .foregroundStyle(.black)
                .background(.orange, in: .capsule)
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .accessibilityIdentifier("testModeBanner")
        .accessibilityHint("Opens test data settings")
    }
}
