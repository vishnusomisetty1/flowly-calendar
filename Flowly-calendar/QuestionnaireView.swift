import SwiftUI

struct QuestionnaireView: View {
    @EnvironmentObject private var userStore: UserStore
    @Binding var currentScreen: ContentView.Screen
    @Binding var user: User

    @State private var cardOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 20) {
            ScrollView {
                VStack(spacing: 25) {
                    VStack(spacing: 8) {
                        Text("Tell Us About Yourself")
                            .font(.title2)
                            .bold()
                        Text("Let's create your perfect study schedule! 🎓")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("What do you do when you get home?").font(.headline)
                        TextField("e.g., snack, rest, check phone", text: $user.homeActivity)
                            .textFieldStyle(.roundedBorder).padding(.vertical, 5)
                    }

                    Group {
                        LabeledDatePicker(title: "When do you start studying?", date: $user.studyStartTime)
                        LabeledDatePicker(title: "When do you eat dinner?", date: $user.dinnerTime)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("How long is dinner? (minutes)").font(.headline)
                            Stepper(value: $user.dinnerDuration, in: 15...120, step: 5) {
                                Text("\(user.dinnerDuration) minutes")
                            }
                        }
                        LabeledDatePicker(title: "What time do you sleep?", date: $user.sleepTime)

                        // Study Strategy Selection
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Choose Your Study Strategy").font(.headline)
                            VStack(spacing: 10) {
                                ForEach([StudyStrategy.activeRecall, StudyStrategy.spacedRepetition, StudyStrategy.pomodoro], id: \.self) { strategy in
                                    StudyStrategyCard(strategy: strategy, selectedStrategy: $user.studyStrategy)
                                }
                            }
                        }
                    }
                }
            }

            HStack(spacing: 15) {
                Button { currentScreen = .welcome } label: {
                    Text("Back").font(.headline).foregroundColor(.blue)
                        .frame(maxWidth: .infinity).padding().background(Color(.systemGray6)).cornerRadius(10)
                }
                Button {
                    userStore.user = user

                    // If already done onboarding, go straight to schedule
                    if userStore.onboardingDone {
                        currentScreen = .schedule
                    } else {
                        userStore.onboardingDone = true
                        currentScreen = .googleSignIn
                    }
                } label: {
                    Text("Save").font(.headline).foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding().background(Color.blue).cornerRadius(10)
                }
            }
        }
        .padding()
    }
}

private struct LabeledDatePicker: View {
    let title: String
    @Binding var date: Date
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            DatePicker("", selection: $date, displayedComponents: .hourAndMinute)
                .datePickerStyle(.compact)
        }
    }
}

private struct StudyStrategyCard: View {
    let strategy: StudyStrategy
    @Binding var selectedStrategy: StudyStrategy
    @State private var isPressed = false

    var isSelected: Bool {
        selectedStrategy == strategy
    }

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                selectedStrategy = strategy
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isPressed = false
            }
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(Color.white.opacity(0.3))
                            .frame(width: 56, height: 56)
                    } else {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [strategyColor.opacity(0.2), strategyColor.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 56, height: 56)
                    }

                    Image(systemName: strategy.icon)
                        .font(.title2)
                        .foregroundColor(isSelected ? .white : strategyColor)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(strategy.displayName)
                        .font(.headline)
                        .foregroundColor(isSelected ? .white : .primary)
                    Text(strategy.description)
                        .font(.subheadline)
                        .foregroundColor(isSelected ? .white.opacity(0.9) : .secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if isSelected {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.3))
                            .frame(width: 32, height: 32)
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.white)
                            .font(.title3)
                    }
                }
            }
            .padding(20)
            .background(
                isSelected
                    ? LinearGradient(
                        colors: [strategyColor.opacity(0.9), strategyColor],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    : LinearGradient(
                        colors: [Color.white, Color(.systemGray6).opacity(0.5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
            )
            .cornerRadius(20)
            .shadow(color: isSelected ? strategyColor.opacity(0.3) : Color.black.opacity(0.1), radius: isSelected ? 12 : 6, x: 0, y: isSelected ? 6 : 2)
            .scaleEffect(isPressed ? 0.95 : (isSelected ? 1.02 : 1.0))
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
            .animation(.easeOut(duration: 0.1), value: isPressed)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    private var strategyColor: Color {
        switch strategy {
        case .activeRecall: return Color.purple
        case .spacedRepetition: return Color.orange
        case .pomodoro: return Color.green
        }
    }
}
