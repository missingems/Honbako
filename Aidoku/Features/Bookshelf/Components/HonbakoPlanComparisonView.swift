#if SUMI
import SwiftUI

struct HonbakoPlanComparisonView: View {
    let proPrice: String?

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 16) {
            GridRow(alignment: .top) {
                Text("Your Plan").font(.subheadline).foregroundStyle(.secondary)
                VStack(alignment: .center, spacing: 4) {
                    Text("Honbako.Plan.Free").font(.headline)
                    Text("No charge").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                VStack(alignment: .center, spacing: 4) {
                    Text("Honbako.Plan.Pro").font(.headline).foregroundStyle(.tint)
                    if let proPrice {
                        Text(proPrice).font(.subheadline.bold())
                        Text("per month").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Monthly Subscription").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            Divider().gridCellUnsizedAxes(.horizontal)
            feature("Read your collection", free: true, pro: true)
            feature("Read imported files offline", free: true, pro: true)
            feature("Download chapters for offline reading", free: false, pro: true)
            feature("New chapter notifications", free: false, pro: true)
            feature("iCloud Sync", free: false, pro: true)
            feature("Honbako.Plan.AdFree", free: true, pro: true)
        }
        .font(.subheadline)
        .padding(.vertical, 8)
        .accessibilityIdentifier("Honbako.Plan.Comparison")
    }

    private func feature(_ title: LocalizedStringKey, free: Bool, pro: Bool) -> some View {
        GridRow {
            Text(title).fixedSize(horizontal: false, vertical: true)
            availability(free, plan: "Free")
            availability(pro, plan: "Pro")
        }
        .accessibilityElement(children: .combine)
    }

    private func availability(_ included: Bool, plan: String) -> some View {
        Image(systemName: included ? "checkmark" : "minus")
            .foregroundStyle(included ? Color.accentColor : Color.secondary)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(included ? String(localized: "Included with \(plan)") : String(localized: "Not included with \(plan)"))
    }
}
#endif
