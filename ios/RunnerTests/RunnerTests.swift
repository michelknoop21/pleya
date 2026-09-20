import Flutter
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

  func testExample() {
    // If you add code to the Runner application, consider adding tests here.
    // See https://developer.apple.com/documentation/xctest for more information about using XCTest.
  }

  func testMpvTeardownCompletionWaitsForQueuedDestroy() {
    let destroyStarted = expectation(description: "destroy started")
    let destroyMayFinish = DispatchSemaphore(value: 0)
    let completionCalled = expectation(description: "completion called after destroy")
    let queue = DispatchQueue(label: "test.mpv.teardown")
    var destroyed = false
    var completed = false

    MpvTeardownScheduler.run(
      on: queue,
      destroy: {
        destroyStarted.fulfill()
        destroyMayFinish.wait()
        destroyed = true
      },
      completionQueue: .main,
      completion: {
        XCTAssertTrue(destroyed)
        completed = true
        completionCalled.fulfill()
      }
    )

    wait(for: [destroyStarted], timeout: 1)
    XCTAssertFalse(completed)
    destroyMayFinish.signal()
    wait(for: [completionCalled], timeout: 1)
  }

}
