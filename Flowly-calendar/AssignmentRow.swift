import SwiftUI

struct AssignmentRow: View {
    let assignment: Assignment
    
    @EnvironmentObject private var assignmentsStore: AssignmentsStore
    @State private var showDeleteAlert = false
    @State private var finalDeleteVerification = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(assignment.title)
                    .font(.body)
                    .fontWeight(.medium)

                HStack(spacing: 16) {
                    Label(formattedDate(assignment.dueDate, hasRealDueDate: assignment.hasRealDueDate), systemImage: "calendar")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if assignment.aiEstimatedTime > 0 {
                        Label("Estimated: \(formattedMinutes(assignment.aiEstimatedTime))", systemImage: "clock")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if assignment.aiEstimatedImportance > 0 {
                        Label("Importance: \(assignment.aiEstimatedImportance)", systemImage: "star.fill")
                            .font(.caption)
                            .foregroundColor(.yellow)
                    }
                }
            }
            Spacer()
            VStack(spacing: 8) {
                Button {
                    showDeleteAlert = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(BorderlessButtonStyle())
                Button {
                    // Use the store's toggleCompletion, which persists to UserDefaults
                    assignmentsStore.toggleCompletion(for: assignment.id)
                } label: {
                    Image(systemName: assignment.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(assignment.isCompleted ? .green : .secondary)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
        }
        .padding(.vertical, 4)
        .alert("Delete Assignment?", isPresented: $showDeleteAlert, actions: {
            Button("Delete", role: .destructive) {
                finalDeleteVerification = true
                showDeleteAlert = false
            }
            Button("Cancel", role: .cancel) { }
        }, message: {
            Text("Are you sure you want to delete this assignment?")
        })
        .alert("Are you sure you want to permanently delete this assignment? This action cannot be undone.", isPresented: $finalDeleteVerification, actions: {
            Button("Delete", role: .destructive) {
                assignmentsStore.assignments.removeAll { $0.id == assignment.id }
                finalDeleteVerification = false
            }
            Button("Cancel", role: .cancel) {
                finalDeleteVerification = false
            }
        })
    }

    private func formattedDate(_ date: Date, hasRealDueDate: Bool) -> String {
        if !hasRealDueDate {
            return "No Due Date"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formattedMinutes(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}

#Preview {
    let sample = Assignment(
        id: UUID(),
        title: "Sample Assignment",
        dueDate: Date(),
        classroom: "Math",
        description: "Read chapter 5",
        courseId: nil,
        isCompleted: false,
        hasRealDueDate: true,
        aiEstimatedImportance: 3,
        aiEstimatedTime: 45
    )
    return AssignmentRow(assignment: sample)
        .padding()
        .previewLayout(.sizeThatFits)
}
