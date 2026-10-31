#if SUMI
import SwiftUI

struct HonbakoAutomationApprovalView: View {
    let jobID: String
    @ObservedObject private var service = HonbakoAutomationService.shared
    @Environment(\.dismiss) private var dismiss
    private var approval: HonbakoAutomationModels.Approval? { service.pendingApprovals.first { $0.id == jobID } }

    var body: some View {
        List {
            Group {
                if let approval {
                    Section {
                        if approval.isSourceChange {
                            Text(approval.title).font(.headline)
                            Text(approval.items.first?.title ?? "Source change")
                            if let detail = approval.detail { Text(detail).font(.footnote).foregroundStyle(.secondary) }
                        }
                        ForEach(Array((approval.isSourceChange ? [] : approval.items).enumerated()), id: \.offset) { _, item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title).font(.headline)
                                Text(service.sourceName(for: item.sourceId)).foregroundStyle(.secondary)
                            }
                        }
                    } header: { Text(approval.isSourceChange ? "Source Change Requested By Your AI"
                        : approval.isRemoval ? "Books Your AI Asked to Remove" : "Books Requested By Your AI") }
                    footer: {
                        Text(approval.isSourceChange
                            ? "Only this change will be applied. Extension repositories can supply extensions that run in Honbako. Approve only repositories you trust. Removing a source can prevent its books from opening until it is reinstalled."
                            : approval.isRemoval
                            ? "These books will be removed from your library, the same as Remove from Library. Your reading history is kept, and you can add them again later."
                            : "These books will be saved from connections already in Honbako. Books already in your library will be kept once.")
                    }

                    Section {
                        Button(role: approval.isRemoval ? .destructive : nil) {
                            service.approve(jobID: jobID)
                        } label: {
                            if service.approvingJobID == jobID { ProgressView().frame(maxWidth: .infinity) }
                            else { Text(approval.isSourceChange ? "Approve Source Change" : approval.isRemoval ? "Remove Books" : "Approve and Add Books") }
                        }
                        .disabled(service.approvingJobID != nil || !service.isEnabled)
                        .accessibilityIdentifier("Honbako.Automation.Approve.\(jobID)")
                        Button("Reject Request", role: .destructive) {
                            Task { await service.reject(jobID: jobID) }
                        }
                        .disabled(service.approvingJobID != nil)
                        .accessibilityIdentifier("Honbako.Automation.Reject.\(jobID)")
                    }
                } else if let handled = service.handledNotice(for: jobID) {
                    ContentUnavailableView("Handled on \(handled.deviceName)", systemImage: "checkmark.circle",
                        description: Text("Another of your devices already answered this request."))
                } else {
                    ContentUnavailableView("Request Finished", systemImage: "checkmark.circle",
                        description: Text("This request is no longer waiting for approval."))
                }
            }
            .honbakoPaperRows()
        }
        .honbakoPaperListBackground()
        .navigationTitle(approval?.isSourceChange == true ? "Review Source Change" : approval?.isRemoval == true ? "Review Removal" : "Review Books")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: approval == nil) { if approval == nil, service.handledNotice(for: jobID) == nil { dismiss() } }
    }
}
#endif
