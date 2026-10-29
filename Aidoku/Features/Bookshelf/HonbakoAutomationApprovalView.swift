#if SUMI
import SwiftUI

struct HonbakoAutomationApprovalView: View {
    let jobID: String
    @ObservedObject private var service = HonbakoAutomationService.shared
    @Environment(\.dismiss) private var dismiss
    private var approval: HonbakoAutomationModels.Approval? { service.pendingApprovals.first { $0.id == jobID } }

    var body: some View {
        List {
            if let approval {
                Section {
                    ForEach(Array(approval.items.enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title).font(.headline)
                            Text(service.sourceName(for: item.sourceId)).foregroundStyle(.secondary)
                        }
                    }
                } header: { Text("Books Requested By Your Assistant") }
                footer: { Text("These books will be saved from connections already in Honbako. Books already in your library will be kept once.") }

                Section {
                    Button {
                        service.approve(jobID: jobID)
                    } label: {
                        if service.approvingJobID == jobID { ProgressView().frame(maxWidth: .infinity) }
                        else { Text("Approve and Add Books") }
                    }
                    .disabled(service.approvingJobID != nil || !service.isEnabled)
                    .accessibilityIdentifier("Honbako.Automation.Approve.\(jobID)")
                    Button("Reject Request", role: .destructive) {
                        Task { await service.reject(jobID: jobID) }
                    }
                    .disabled(service.approvingJobID != nil)
                    .accessibilityIdentifier("Honbako.Automation.Reject.\(jobID)")
                }
            } else {
                ContentUnavailableView("Request Finished", systemImage: "checkmark.circle",
                    description: Text("This request is no longer waiting for approval."))
            }
        }
        .navigationTitle("Review Books")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: approval == nil) { if approval == nil { dismiss() } }
    }
}
#endif
