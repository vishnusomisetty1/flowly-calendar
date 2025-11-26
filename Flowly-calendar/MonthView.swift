// TODO: Minimum time block setting not found; please specify where the time block duration is handled.
import SwiftUI

struct MonthView: View {
    @EnvironmentObject private var assignmentsStore: AssignmentsStore
    
    @State private var currentDate = Date()
    @State private var selectedDate: Date?
    
    private var calendar = Calendar.current
    private let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Month/Year Header with Navigation
                HStack {
                    Button(action: previousMonth) {
                        Image(systemName: "chevron.left")
                            .foregroundColor(.blue)
                    }
                    
                    Spacer()
                    
                    Text(monthYearString)
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    Button(action: nextMonth) {
                        Image(systemName: "chevron.right")
                            .foregroundColor(.blue)
                    }
                }
                .padding()
                
                // Weekday headers
                HStack(spacing: 0) {
                    ForEach(weekdays, id: \.self) { weekday in
                        Text(weekday)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal)
                
                // Calendar grid - only show days of current month
                let days = daysInMonth
                let firstWeekday = calendar.component(.weekday, from: days.first ?? Date()) - 1 // 0 = Sunday
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                    // Empty cells for days before month starts
                    ForEach(0..<firstWeekday, id: \.self) { _ in
                        Color.clear
                            .frame(width: 44, height: 50)
                    }
                    
                    // Days of the month
                    ForEach(days, id: \.self) { date in
                        DayCell(date: date, 
                               hasAssignment: hasAssignment(on: date),
                               isSelected: selectedDate != nil && calendar.isDate(date, inSameDayAs: selectedDate!),
                               isToday: calendar.isDateInToday(date),
                               isCurrentMonth: true)
                        .onTapGesture {
                            selectedDate = date
                        }
                    }
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .navigationTitle("Month")
        }
        .sheet(item: Binding(
            get: { selectedDate.map { DaySheetItem(date: $0) } },
            set: { selectedDate = $0?.date }
        )) { item in
            DayAssignmentsView(date: item.date)
                .presentationDetents([.medium, .large])
        }
    }
    
    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: currentDate)
    }
    
    private var daysInMonth: [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: currentDate),
              let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: currentDate)) else {
            return []
        }
        
        var days: [Date] = []
        
        // Add only days of current month
        var currentDay = firstDay
        while currentDay < monthInterval.end {
            days.append(currentDay)
            if let nextDay = calendar.date(byAdding: .day, value: 1, to: currentDay) {
                currentDay = nextDay
            } else {
                break
            }
        }
        
        return days
    }
    
    private func hasAssignment(on date: Date) -> Bool {
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        
        return assignmentsStore.assignments.contains { assignment in
            guard assignment.hasRealDueDate && !assignment.isCompleted else { return false }
            let assignmentDate = calendar.startOfDay(for: assignment.dueDate)
            return assignmentDate >= startOfDay && assignmentDate < endOfDay
        }
    }
    
    private func previousMonth() {
        if let date = calendar.date(byAdding: .month, value: -1, to: currentDate) {
            currentDate = date
            selectedDate = nil
        }
    }
    
    private func nextMonth() {
        if let date = calendar.date(byAdding: .month, value: 1, to: currentDate) {
            currentDate = date
            selectedDate = nil
        }
    }
}

struct DayCell: View {
    let date: Date
    let hasAssignment: Bool
    let isSelected: Bool
    let isToday: Bool
    let isCurrentMonth: Bool
    
    private var dayNumber: Int {
        Calendar.current.component(.day, from: date)
    }
    
    var body: some View {
        VStack(spacing: 4) {
            Text("\(dayNumber)")
                .font(.system(size: 16, weight: isToday ? .bold : .regular))
                .foregroundColor(isCurrentMonth ? (isToday ? .blue : .primary) : .secondary)
            
            if hasAssignment {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 6, height: 6)
            } else {
                Spacer()
                    .frame(height: 6)
            }
        }
        .frame(width: 44, height: 50)
        .background(isSelected ? Color.blue.opacity(0.2) : Color.clear)
        .cornerRadius(8)
    }
}

struct DaySheetItem: Identifiable {
    let id = UUID()
    let date: Date
}

struct DayAssignmentsView: View {
    @EnvironmentObject private var assignmentsStore: AssignmentsStore
    
    let date: Date
    private let calendar = Calendar.current
    
    private var assignmentsForDay: [Assignment] {
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        
        return assignmentsStore.assignments.filter { assignment in
            guard assignment.hasRealDueDate else { return false }
            let assignmentDate = calendar.startOfDay(for: assignment.dueDate)
            return assignmentDate >= startOfDay && assignmentDate < endOfDay
        }
        .sorted { $0.dueDate < $1.dueDate }
    }
    
    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter.string(from: date)
    }
    
    var body: some View {
        NavigationView {
            List {
                if assignmentsForDay.isEmpty {
                    Text("No assignments due on this day")
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    ForEach(assignmentsForDay) { assignment in
                        AssignmentRow(assignment: assignment)
                    }
                }
            }
            .navigationTitle(dateString)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

