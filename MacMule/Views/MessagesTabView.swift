import SwiftUI

struct MessagesTabView: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "message")
                .font(.system(size: 48))
                .foregroundStyle(.secondary.opacity(0.5))
            
            Text("Messages unavailable")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            Text("The messaging and friends system requires a connection to the eD2k network.\nThis feature will be implemented in a future version.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
            
            Spacer()
        }
        .frame(maxWidth: 300)
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    MessagesTabView()
}
