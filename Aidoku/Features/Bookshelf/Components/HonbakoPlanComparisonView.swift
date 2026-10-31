#if SUMI
import SwiftUI

/// Benefits compare tiers; localized billing choices appear separately below.
struct HonbakoPlanComparisonView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var features: [(LocalizedStringKey, Bool)] {
        var rows: [(LocalizedStringKey, Bool)] = [
            ("Your own collection", true),
            ("Local MCP server", true),
            ("iCloud sync", true),
            ("Resume widget", true)
        ]
        #if HONBAKO_EXTERNAL_SOURCES
        rows.append(("Extension repositories", true))
        #endif
        rows += [
            ("Remote MCP server", false),
            ("Duo cover mode", false),
            ("Japanese reading guide", false),
            ("Downloads and alerts", false),
            ("Reading time and update widgets", false)
        ]
        return rows
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        header("Free")
                        header("Pro")
                    }
                    ForEach(features.indices, id: \.self) { index in
                        let (title, free) = features[index]
                        Divider()
                        VStack(alignment: .leading, spacing: 12) {
                            Text(title).font(.headline)
                            HStack {
                                accessibleInclusion(free, plan: "Free")
                                accessibleInclusion(true, plan: "Pro")
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            } else {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 14) {
                    GridRow(alignment: .top) {
                        Text("Included")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        header("Free")
                        header("Pro")
                    }
                    Divider().gridCellColumns(3)
                    ForEach(features.indices, id: \.self) { index in
                        let (title, free) = features[index]
                        GridRow {
                            Text(title)
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            inclusion(free, plan: "Free")
                            inclusion(true, plan: "Pro")
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .accessibilityIdentifier("Honbako.Plan.Comparison")
    }

    private func header(_ name: LocalizedStringKey) -> some View {
        Text(name)
            .font(.headline)
            .frame(maxWidth: .infinity)
            .gridColumnAlignment(.center)
    }

    private func accessibleInclusion(_ included: Bool, plan: String) -> some View {
        Label(plan, systemImage: included ? "checkmark" : "minus")
            .font(.subheadline)
            .foregroundStyle(included ? Color.accentColor : Color.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("\(plan): \(included ? "included" : "not included")")
    }

    private func inclusion(_ included: Bool, plan: String) -> some View {
        Image(systemName: included ? "checkmark" : "minus")
            .font(.body.weight(.semibold))
            .foregroundStyle(included ? Color.accentColor : Color.secondary)
            .frame(maxWidth: .infinity, minHeight: 24)
            .accessibilityLabel("\(plan): \(included ? "included" : "not included")")
    }
}
#endif
