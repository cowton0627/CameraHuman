//
//  CameraManualControlsTests.swift
//  CameraHumanTests
//

import XCTest
import CoreMedia
@testable import CameraHuman

final class CameraManualControlsTests: XCTestCase {

    // MARK: - supportedStandardFrameRates

    func test_supportedFrameRates_typical60Device_returnsAllThree() {
        let rates = CameraManualControls.supportedStandardFrameRates(minFrameRate: 1, maxFrameRate: 60)
        XCTAssertEqual(rates, [24, 30, 60])
    }

    func test_supportedFrameRates_30Cap_dropsSixty() {
        let rates = CameraManualControls.supportedStandardFrameRates(minFrameRate: 1, maxFrameRate: 30)
        XCTAssertEqual(rates, [24, 30])
    }

    func test_supportedFrameRates_highFloor_dropsTwentyFour() {
        let rates = CameraManualControls.supportedStandardFrameRates(minFrameRate: 30, maxFrameRate: 60)
        XCTAssertEqual(rates, [30, 60])
    }

    func test_supportedFrameRates_zeroMax_returnsEmpty() {
        XCTAssertTrue(CameraManualControls.supportedStandardFrameRates(minFrameRate: 0, maxFrameRate: 0).isEmpty)
    }

    // MARK: - frameDuration

    func test_frameDuration_30fps_isOneOver30() {
        let duration = CameraManualControls.frameDuration(forFPS: 30)
        XCTAssertEqual(duration.timescale, 30)
        XCTAssertEqual(duration.value, 1)
    }

    func test_frameDuration_roundsFractional() {
        let duration = CameraManualControls.frameDuration(forFPS: 29.97)
        XCTAssertEqual(duration.timescale, 30)
    }

    func test_frameDuration_zeroClampsToOne() {
        let duration = CameraManualControls.frameDuration(forFPS: 0)
        XCTAssertEqual(duration.timescale, 1)
    }

    // MARK: - nextFrameRate (cycle)

    func test_nextFrameRate_cyclesForward() {
        let supported = [24.0, 30.0, 60.0]
        XCTAssertEqual(CameraManualControls.nextFrameRate(after: 24, in: supported), 30)
        XCTAssertEqual(CameraManualControls.nextFrameRate(after: 30, in: supported), 60)
    }

    func test_nextFrameRate_wrapsAround() {
        let supported = [24.0, 30.0, 60.0]
        XCTAssertEqual(CameraManualControls.nextFrameRate(after: 60, in: supported), 24)
    }

    func test_nextFrameRate_currentNotInList_returnsFirst() {
        XCTAssertEqual(CameraManualControls.nextFrameRate(after: 120, in: [24, 30]), 24)
    }

    func test_nextFrameRate_emptyList_returnsNil() {
        XCTAssertNil(CameraManualControls.nextFrameRate(after: 30, in: []))
    }

    func test_nextFrameRate_toleratesFloatingPointJitter() {
        XCTAssertEqual(CameraManualControls.nextFrameRate(after: 30.0001, in: [24, 30, 60]), 60)
    }

    // MARK: - clamp

    func test_clampFloat_belowMin() {
        XCTAssertEqual(CameraManualControls.clamp(Float(-5), min: 0, max: 10), 0)
    }

    func test_clampFloat_aboveMax() {
        XCTAssertEqual(CameraManualControls.clamp(Float(99), min: 0, max: 10), 10)
    }

    func test_clampFloat_inRange() {
        XCTAssertEqual(CameraManualControls.clamp(Float(5), min: 0, max: 10), 5)
    }

    func test_clamp_invertedRange_returnsLower() {
        XCTAssertEqual(CameraManualControls.clamp(Float(5), min: 10, max: 0), 10)
    }

    // MARK: - slider mapping round-trip

    func test_sliderMapping_roundTrip() {
        let value = CameraManualControls.value(forSliderPosition: 0.5, min: 100, max: 3200)
        XCTAssertEqual(value, 1650, accuracy: 0.5)
        let position = CameraManualControls.sliderPosition(forValue: value, min: 100, max: 3200)
        XCTAssertEqual(position, 0.5, accuracy: 0.001)
    }

    func test_sliderPosition_clampsOutOfRangeValue() {
        XCTAssertEqual(CameraManualControls.sliderPosition(forValue: 5000, min: 100, max: 3200), 1)
        XCTAssertEqual(CameraManualControls.sliderPosition(forValue: 0, min: 100, max: 3200), 0)
    }

    func test_value_clampsOutOfRangePosition() {
        XCTAssertEqual(CameraManualControls.value(forSliderPosition: 2, min: 0, max: 100), 100)
        XCTAssertEqual(CameraManualControls.value(forSliderPosition: -1, min: 0, max: 100), 0)
    }

    // MARK: - shutterText

    func test_shutterText_standard() {
        XCTAssertEqual(CameraManualControls.shutterText(forSeconds: 1.0 / 48.0), "1/48")
    }

    func test_shutterText_zero_isAuto() {
        XCTAssertEqual(CameraManualControls.shutterText(forSeconds: 0), "AUTO")
    }
}
