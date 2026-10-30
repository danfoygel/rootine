import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "leaf")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Rootine")
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
