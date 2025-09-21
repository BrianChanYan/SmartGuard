//
//  TaskView.swift
//  SmartGuard
//
//  Created by Brian Chan on 2025/9/20.
//

import SwiftUI

struct TaskView: View {
    @State private var resetTrigger = false
    @EnvironmentObject var familyStatusManager: FamilyStatusManager
    @EnvironmentObject var securityManager: SecurityAlertManager
    @State private var apiService: FamilyAPIService?
    @State private var showingAddMember = false

    var body: some View {
        ZStack {
            Color(red: 0x09/255.0, green: 0x09/255.0, blue: 0x09/255.0).ignoresSafeArea()

            VStack(spacing: 20) {
                // Top Bar
                HStack {
                    Text("Family")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(Color(red: 255/255, green: 129/255, blue: 79/255))

                    Spacer()

                    Image("face")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)

                if securityManager.isGuardModeActive {
                    HStack(spacing: 12) {
                        Button(action: {
                            securityManager.processDetection(name: "Unknown")
                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                            impactFeedback.impactOccurred()
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "person.fill.questionmark")
                                    .foregroundColor(.orange)
                                    .font(.caption)
                                Text("Test Unknown")
                                    .foregroundColor(.orange)
                                    .font(.caption)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.orange.opacity(0.2))
                            .cornerRadius(8)
                        }

                        Button(action: {
                            if let firstMember = apiService?.familyMembers.first {
                                securityManager.processDetection(name: firstMember.name)
                            }
                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                            impactFeedback.impactOccurred()
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "person.fill.checkmark")
                                    .foregroundColor(.green)
                                    .font(.caption)
                                Text("Test Member")
                                    .foregroundColor(.green)
                                    .font(.caption)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.green.opacity(0.2))
                            .cornerRadius(8)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 20)
                }

                // Add New Family Member Button
                Button(action: {
                    let selectionFeedback = UISelectionFeedbackGenerator()
                    selectionFeedback.selectionChanged()
                    showingAddMember = true
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "person.badge.plus.fill")
                            .foregroundColor(Color(red: 255/255, green: 129/255, blue: 79/255))
                            .font(.title2)

                        Text("Add Family Member")
                            .foregroundColor(.white)
                            .font(.headline)
                            .fontWeight(.medium)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .foregroundColor(.gray)
                            .font(.system(size: 14, weight: .medium))
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, 20)
                    .background(Color.gray.opacity(0.15))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(red: 255/255, green: 129/255, blue: 79/255).opacity(0.3), lineWidth: 1)
                    )
                }
                .padding(.horizontal, 20)

                // Family Members List
                if apiService?.isLoading == true {
                    ProgressView("Loading family members...")
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if apiService?.familyMembers.isEmpty != false {
                    VStack(spacing: 16) {
                        Image(systemName: "person.3")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        Text("No family members registered")
                            .font(.headline)
                            .foregroundColor(.gray)
                        Text("Tap 'Add Family Member' to get started")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            ForEach(apiService?.familyMembers ?? []) { member in
                                FamilyMemberItem(
                                    member: member,
                                    resetTrigger: $resetTrigger,
                                    statusManager: familyStatusManager
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }

                if let errorMessage = apiService?.errorMessage {
                    Text("Error: \(errorMessage)")
                        .foregroundColor(.red)
                        .padding()
                }

                Spacer()
            }
        }
        .onAppear {
            if apiService == nil {
                apiService = FamilyAPIService(statusManager: familyStatusManager)
            }
            apiService?.loadFamilyMembers()
        }
        .refreshable {
            apiService?.loadFamilyMembers(forceRefresh: true)
        }
        .onDisappear {
            resetTrigger.toggle()
        }
        .sheet(isPresented: $showingAddMember) {
            if let apiService = apiService {
                AddFamilyMemberView(apiService: apiService)
            }
        }
        .onChange(of: showingAddMember) { isShowing in
            if !isShowing {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    apiService?.loadFamilyMembers(forceRefresh: true)
                }
            }
        }
    }
}

struct FamilyMemberItem: View {
    let member: FamilyMember
    @Binding var resetTrigger: Bool
    @ObservedObject var statusManager: FamilyStatusManager

    @State private var isExpanded = false

    init(member: FamilyMember, resetTrigger: Binding<Bool>, statusManager: FamilyStatusManager) {
        self.member = member
        self._resetTrigger = resetTrigger
        self.statusManager = statusManager
    }

    private var currentStatus: FamilyMemberStatus {
        statusManager.getStatus(for: member.name)
    }

    private var details: [String] {
        var detailArray: [String] = []

        let formatter = DateFormatter()
        formatter.dateStyle = .medium

        detailArray.append("Registered: \(formatter.string(from: member.registeredDate))")

        if let lastSeen = member.lastSeen {
            detailArray.append("Last Seen: \(formatter.string(from: lastSeen))")
        } else {
            detailArray.append("Last Seen: Never")
        }

        detailArray.append("Recognition Count: \(member.recognitionCount)")
        detailArray.append("Relationship: \(member.relationship)")

        return detailArray
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main family member row
            HStack {
                // Family member avatar
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.2))
                        .frame(width: 45, height: 45)

                    Image(systemName: familyIcon(for: member.relationship))
                        .foregroundColor(.green)
                        .font(.title3)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(member.name)
                        .foregroundColor(.white)
                        .font(.headline)

                    Text(member.relationship)
                        .foregroundColor(.green)
                        .font(.subheadline)
                }

                Spacer()

                // Status indicator
                statusIndicatorView

                // Expand/collapse indicator
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .foregroundColor(.gray)
                    .font(.system(size: 14, weight: .medium))
                    .rotationEffect(.degrees(isExpanded ? 0 : 0))
                    .animation(.easeInOut(duration: 0.2), value: isExpanded)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(Color.gray.opacity(0.2))
            .cornerRadius(12)
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isExpanded.toggle()
                }

                // Add haptic feedback
                let selectionFeedback = UISelectionFeedbackGenerator()
                selectionFeedback.selectionChanged()
            }

            // Expanded details
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(details.indices, id: \.self) { index in
                        HStack(alignment: .top, spacing: 12) {
                            Circle()
                                .fill(Color(red: 255/255, green: 129/255, blue: 79/255))
                                .frame(width: 6, height: 6)
                                .padding(.top, 6)

                            Text(details[index])
                                .foregroundColor(.white.opacity(0.9))
                                .font(.subheadline)
                                .multilineTextAlignment(.leading)

                            Spacer()
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal, 4)
                .padding(.top, 4)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity.combined(with: .move(edge: .top))
                ))
            }
        }
        .onChange(of: resetTrigger) { _ in
                withAnimation(.easeInOut(duration: 0.3)) {
                isExpanded = false
            }
        }
    }

    private var statusIndicatorView: some View {
        HStack(spacing: 6) {
            Image(systemName: statusIcon)
                .font(.caption)
                .foregroundColor(statusColor)

            Text(currentStatus.rawValue)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(statusColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusBackgroundColor)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(statusBorderColor, lineWidth: 1)
        )
    }

    private var statusIcon: String {
        currentStatus.icon
    }

    private var statusColor: Color {
        currentStatus == .home ? .green : .orange
    }

    private var statusBackgroundColor: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(currentStatus == .home ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
    }

    private var statusBorderColor: Color {
        currentStatus == .home ? Color.green.opacity(0.6) : Color.orange.opacity(0.6)
    }


    private func familyIcon(for relationship: String) -> String {
        switch relationship.lowercased() {
        case "father", "dad":
            return "mustache.fill"
        case "mother", "mom":
            return "figure.dress.line.vertical.figure"
        case "son":
            return "figure.child"
        case "daughter":
            return "figure.child"
        default:
            return "person.fill"
        }
    }
}
