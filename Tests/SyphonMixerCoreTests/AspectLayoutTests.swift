import XCTest
@testable import SyphonMixerCore

final class AspectLayoutTests: XCTestCase {
    func testFillCropCropsWideSourceHorizontally() {
        let mapping = AspectLayout.mapping(
            source: MixerSize(width: 1920, height: 1080),
            output: MixerSize(width: 1080, height: 1080),
            mode: .fillCrop
        )

        XCTAssertEqual(mapping.destination, .full)
        XCTAssertEqual(mapping.uv.y, 0.0, accuracy: 0.0001)
        XCTAssertEqual(mapping.uv.height, 1.0, accuracy: 0.0001)
        XCTAssertEqual(mapping.uv.width, 0.5625, accuracy: 0.0001)
        XCTAssertEqual(mapping.uv.x, 0.21875, accuracy: 0.0001)
    }

    func testFillCropCropsTallSourceVertically() {
        let mapping = AspectLayout.mapping(
            source: MixerSize(width: 1080, height: 1920),
            output: MixerSize(width: 1920, height: 1080),
            mode: .fillCrop
        )

        XCTAssertEqual(mapping.destination, .full)
        XCTAssertEqual(mapping.uv.x, 0.0, accuracy: 0.0001)
        XCTAssertEqual(mapping.uv.width, 1.0, accuracy: 0.0001)
        XCTAssertEqual(mapping.uv.height, 0.31640625, accuracy: 0.0001)
        XCTAssertEqual(mapping.uv.y, 0.341796875, accuracy: 0.0001)
    }

    func testFitLetterboxesWideSourceInSquareOutput() {
        let mapping = AspectLayout.mapping(
            source: MixerSize(width: 1920, height: 1080),
            output: MixerSize(width: 1080, height: 1080),
            mode: .fit
        )

        XCTAssertEqual(mapping.uv, .full)
        XCTAssertEqual(mapping.destination.width, 1.0, accuracy: 0.0001)
        XCTAssertEqual(mapping.destination.height, 0.5625, accuracy: 0.0001)
        XCTAssertEqual(mapping.destination.y, 0.21875, accuracy: 0.0001)
    }

    func testStretchUsesFullRects() {
        let mapping = AspectLayout.mapping(
            source: MixerSize(width: 100, height: 400),
            output: MixerSize(width: 3840, height: 1080),
            mode: .stretch
        )

        XCTAssertEqual(mapping.destination, .full)
        XCTAssertEqual(mapping.uv, .full)
    }

    func testSonyParkPixelMapActiveAreaIsTopLeftInFullHD() {
        let canvas = MixerSize(width: 1920, height: 1080)
        let area = PixelMapLayout.activeArea(in: canvas)

        XCTAssertEqual(area.x * canvas.width, 0, accuracy: 0.0001)
        XCTAssertEqual(area.y * canvas.height, 0, accuracy: 0.0001)
        XCTAssertEqual(area.width * canvas.width, 1344, accuracy: 0.0001)
        XCTAssertEqual(area.height * canvas.height, 672, accuracy: 0.0001)
    }

    func testPixelMapDestinationMapsIntoActiveArea() {
        let canvas = MixerSize(width: 1920, height: 1080)
        let area = PixelMapLayout.activeArea(in: canvas)
        let mapped = PixelMapLayout.map(destination: .full, into: area)

        XCTAssertEqual(mapped, area)
    }
}
