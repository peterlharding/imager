import AppKit
import Foundation
import Testing
@testable import Imager

/// Covers the thumbnail cache's bound. Generation itself is QuickLook's, so what is worth testing
/// is that the cache does not grow without limit across a session's browsing.
@Suite("Thumbnail cache")
struct ThumbnailProviderTests {

    private func makeImages(_ count: Int, in directory: URL) -> [URL] {
        (1...count).map { index in
            TestSupport.writePNG(
                TestSupport.solidImage(width: 8, height: 8), named: "image\(index).png", in: directory
            )
        }
    }

    @Test("The cache stops growing at its capacity")
    func evictsBeyondCapacity() async {
        let directory = TestSupport.makeTemporaryDirectory()
        defer { TestSupport.remove(directory) }
        let urls = makeImages(5, in: directory)
        let provider = ThumbnailProvider(capacity: 3)

        for url in urls { _ = await provider.thumbnail(for: url) }

        #expect(await provider.count == 3)
    }

    /// Eviction is first-in, so what goes is what was scrolled away from.
    @Test("The oldest thumbnails are the ones dropped")
    func dropsOldestFirst() async {
        let directory = TestSupport.makeTemporaryDirectory()
        defer { TestSupport.remove(directory) }
        let urls = makeImages(4, in: directory)
        let provider = ThumbnailProvider(capacity: 2)

        for url in urls { _ = await provider.thumbnail(for: url) }

        #expect(await provider.isCached(urls[3]))
        #expect(await provider.isCached(urls[2]))
        #expect(await provider.isCached(urls[0]) == false)
    }

    /// Two visible rows can await the *same uncached* file at once: both miss the cache, both
    /// generate, and both store. If that counted as two entries the cache would evict itself down
    /// below its own capacity. A second request for an already-cached file cannot show this, since
    /// it returns before reaching the store at all.
    @Test("Two rows awaiting one file at once make a single entry")
    func concurrentRequestIsOneEntry() async {
        let directory = TestSupport.makeTemporaryDirectory()
        defer { TestSupport.remove(directory) }
        let urls = makeImages(2, in: directory)
        let provider = ThumbnailProvider(capacity: 2)
        _ = await provider.thumbnail(for: urls[1])

        async let first = provider.thumbnail(for: urls[0])
        async let second = provider.thumbnail(for: urls[0])
        _ = await (first, second)

        #expect(await provider.count == 2)
        #expect(await provider.isCached(urls[1]), "a duplicate entry would have evicted this")
    }

    @Test("A cached thumbnail comes back rather than being regenerated")
    func cachesResults() async throws {
        let directory = TestSupport.makeTemporaryDirectory()
        defer { TestSupport.remove(directory) }
        let url = makeImages(1, in: directory)[0]
        let provider = ThumbnailProvider()

        let first = try #require(await provider.thumbnail(for: url))
        // Removing the file proves the second answer came from the cache.
        TestSupport.remove(url)
        let second = await provider.thumbnail(for: url)

        #expect(second === first)
    }
}
