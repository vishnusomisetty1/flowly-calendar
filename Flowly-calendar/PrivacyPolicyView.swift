import SwiftUI

struct PrivacyPolicyView: View {
    var onAccept: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("Flowly Calendar")
                .font(.largeTitle)
                .bold()
                .foregroundColor(.blue)
                .padding(.top, 60)
                .padding(.horizontal)
                .accessibilityAddTraits(.isHeader)

            Text("Privacy Policy")
                .font(.title)
                .bold()
                .padding(.top, 16)
                .padding(.horizontal)
                .accessibilityAddTraits(.isHeader)

            ScrollView {
                Text(policyText)
                    .font(.body)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                    .padding()
            }
            .frame(maxWidth: .infinity)
            
            Button(action: onAccept) {
                Text("Accept and Continue")
                    .bold()
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(Color(.systemBackground))
                    .cornerRadius(12)
                    .padding([.horizontal, .bottom], 24)
            }
            .accessibilityHint("Read and continue")
        }
        .background(Color(.systemBackground))
        .ignoresSafeArea()
    }

    private var policyText: String {
        """
        Privacy Policy – Flowly Calendar

        Effective Date: [Insert Date]

        Flowly Calendar (“we,” “our,” or “the app”) respects your privacy. This Privacy Policy explains how we collect, use, and store your information when you use our app.

        ⸻

        1. Information We Collect
        Google Classroom Data
            •    We connect to your Google Classroom account to retrieve your courses and assignments.
            •    This data is used only within the app to display your schedule and assignments.

        Email Address
            •    Your Google Classroom email may be displayed in the app to indicate which account is connected.

        ⸻

        2. How We Store Your Information
            •    All assignment data and Google Classroom connection information are stored locally on your device.
            •    Data is stored in Apple’s UserDefaults system or secure device storage.
            •    We do not transmit or share this information with any third parties.

        ⸻

        3. Sharing and Third Parties
            •    We do not sell, share, or transmit your information.
            •    Google Classroom is a third-party service; we only access data you explicitly authorize.

        ⸻

        4. Data Retention
            •    Your assignment data remains on your device until you delete it or disconnect your Google Classroom account.

        ⸻

        5. Your Rights
            •    You can disconnect your Google Classroom account at any time.
            •    You can delete local assignments within the app.

        ⸻

        6. Contact Us
        For questions about privacy, please contact us at:
        Email: [Your Email]
        Website: [Your Website]
        """
    }
}

#Preview {
    PrivacyPolicyView(onAccept: {})
}
