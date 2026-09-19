import Cocoa
import FlutterMacOS
import XCTest

@testable import Runner

class RunnerTests: XCTestCase {

  func testMacOSKeepsMpvGeometryOwnership() {
    XCTAssertTrue(MpvPlayerCoreBase.shouldForwardVideoGeometryPropertyToMpv("video-zoom"))
    XCTAssertTrue(MpvPlayerCoreBase.shouldForwardVideoGeometryPropertyToMpv("panscan"))
    XCTAssertTrue(MpvPlayerCoreBase.shouldForwardVideoGeometryPropertyToMpv("video-aspect-override"))
  }

  func testExample() {
    // If you add code to the Runner application, consider adding tests here.
    // See https://developer.apple.com/documentation/xctest for more information about using XCTest.
  }

}
