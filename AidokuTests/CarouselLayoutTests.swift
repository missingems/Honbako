//
//  CarouselLayoutTests.swift
//  AidokuTests
//

@testable import Aidoku
import Testing
import UIKit

@MainActor
struct CarouselLayoutTests {
    @Test("Carousel pages follow their own container through live width and height changes")
    func containerResize() {
        let layout = CarouselScreenSizingCollectionViewLayout(itemWidth: nil, itemHeight: nil)
        let collectionView = UICollectionView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 200),
            collectionViewLayout: layout
        )

        layout.updateItemSize()
        #expect(layout.itemSize == CGSize(width: 320, height: 200))

        // The same view can resize without moving to another screen or changing traits.
        collectionView.bounds.size = CGSize(width: 700, height: 260)
        layout.updateItemSize()
        #expect(layout.itemSize == CGSize(width: 700, height: 260))

        collectionView.bounds.size = CGSize(width: 280, height: 180)
        layout.updateItemSize()
        #expect(layout.itemSize == CGSize(width: 280, height: 180))
    }

    @Test("An explicitly sized carousel dimension survives a container resize")
    func explicitItemHeight() {
        let layout = CarouselScreenSizingCollectionViewLayout(itemWidth: nil, itemHeight: 210)
        let collectionView = UICollectionView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 400),
            collectionViewLayout: layout
        )
        layout.updateItemSize()
        #expect(layout.itemSize == CGSize(width: 320, height: 210))

        collectionView.bounds.size = CGSize(width: 700, height: 500)
        layout.updateItemSize()
        #expect(layout.itemSize == CGSize(width: 700, height: 210))
    }

    @Test("Resizing a carousel retains the selected manga page")
    func selectedPageSurvivesResize() {
        let layout = CarouselScreenSizingCollectionViewLayout(itemWidth: nil, itemHeight: 210)
        let collectionView = CarouselCollectionView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 210),
            collectionViewFlowLayout: layout
        )
        let dataSource = CarouselTestDataSource()
        defer { withExtendedLifetime(dataSource) {} }
        collectionView.carouselDataSource = dataSource
        collectionView.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "test-cell")
        collectionView.reloadData()
        collectionView.layoutIfNeeded()
        collectionView.currentPage = 1
        collectionView.layoutIfNeeded()

        collectionView.bounds.size = CGSize(width: 700, height: 210)
        collectionView.setNeedsLayout()
        collectionView.layoutIfNeeded()
        #expect(layout.itemSize.width == 700)
        #expect(collectionView.fakeCurrentPage == 2)
        #expect(collectionView.contentOffset.x == 1_400)
        #expect(collectionView.currentPage == 1)

        collectionView.bounds.size = CGSize(width: 280, height: 210)
        collectionView.setNeedsLayout()
        collectionView.layoutIfNeeded()
        #expect(layout.itemSize.width == 280)
        #expect(collectionView.fakeCurrentPage == 2)
        #expect(collectionView.contentOffset.x == 560)
        #expect(collectionView.currentPage == 1)
    }
}

@MainActor
private final class CarouselTestDataSource: CarouselCollectionViewDataSource {
    let numberOfItems = 3

    func carouselCollectionView(
        _ carouselCollectionView: CarouselCollectionView,
        cellForItemAt index: Int,
        fakeIndexPath: IndexPath
    ) -> UICollectionViewCell {
        carouselCollectionView.dequeueReusableCell(withReuseIdentifier: "test-cell", for: fakeIndexPath)
    }

    func pageDidChange(_ page: Int) {}
}
