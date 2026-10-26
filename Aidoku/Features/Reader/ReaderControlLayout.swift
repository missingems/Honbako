//
//  ReaderControlLayout.swift
//  Aidoku
//

import CoreGraphics

enum ReaderControlLayout {
    /// Divide the safe area into rectangles that do not cross active hardware regions.
    static func availableRegions(in bounds: CGRect, avoiding exclusions: [CGRect]) -> [CGRect] {
        exclusions.reduce([bounds]) { regions, exclusion in
            regions.flatMap { region -> [CGRect] in
                let overlap = region.intersection(exclusion)
                guard !overlap.isNull, !overlap.isEmpty else { return [region] }
                return [
                    CGRect(x: region.minX, y: region.minY, width: region.width, height: overlap.minY - region.minY),
                    CGRect(x: region.minX, y: overlap.maxY, width: region.width, height: region.maxY - overlap.maxY),
                    CGRect(x: region.minX, y: overlap.minY, width: overlap.minX - region.minX, height: overlap.height),
                    CGRect(x: overlap.maxX, y: overlap.minY, width: region.maxX - overlap.maxX, height: overlap.height)
                ].filter { !$0.isEmpty }
            }
        }
    }

    static func offset(for frame: CGRect, inside bounds: CGRect, avoiding exclusions: [CGRect]) -> CGPoint {
        let candidates = availableRegions(in: bounds, avoiding: exclusions)
            .filter { $0.width >= frame.width && $0.height >= frame.height }
            .map { region in
                CGPoint(
                    x: min(max(frame.minX, region.minX), region.maxX - frame.width) - frame.minX,
                    y: min(max(frame.minY, region.minY), region.maxY - frame.height) - frame.minY
                )
            }
        return candidates.min { lhs, rhs in
            lhs.x * lhs.x + lhs.y * lhs.y < rhs.x * rhs.x + rhs.y * rhs.y
        } ?? .zero
    }
}
