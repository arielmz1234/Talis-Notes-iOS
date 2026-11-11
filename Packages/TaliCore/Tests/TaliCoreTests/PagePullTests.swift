import Testing
@testable import TaliCore

struct PagePullTests {
  @Test func pullingFarEnoughFromTheEndAddsAPage() {
    var p = PagePull()
    p.begin(below: 32)
    #expect(p.sign(below: 36) == nil)
    #expect(p.sign(below: 100) == .drag(alpha: 1))
    #expect(p.sign(below: 160) == .release(alpha: 1))
    #expect(p.end(below: 160) == .addPage)
    #expect(!p.pulling)
  }

  @Test func lettingGoEarlySpringsBack() {
    var p = PagePull()
    p.begin(below: 30)
    #expect(p.sign(below: 48) == .drag(alpha: 0.25))
    #expect(p.end(below: 120) == .springBack)
  }

  @Test func aScrollThatStartsAboveTheEndIsNoPull() {
    var p = PagePull()
    p.begin(below: -400)
    #expect(p.sign(below: 180) == nil)
    #expect(p.end(below: 180) == .none)
  }

  @Test func whatAlreadyShowsZoomedOutIsNotAPull() {
    var p = PagePull()
    p.begin(below: 500)
    #expect(p.sign(below: 500) == nil)
    #expect(p.end(below: 560) == .springBack)
    p.begin(below: 500)
    #expect(p.end(below: 650) == .addPage)
  }

  @Test func zoomingEndsThePull() {
    var p = PagePull()
    p.begin(below: 32)
    p.cancel()
    #expect(p.sign(below: 200) == nil)
    #expect(p.end(below: 200) == .none)
  }

  @Test func justLookingNeverPulls() {
    var p = PagePull()
    p.begin(below: 32, allowed: false)
    #expect(p.end(below: 200) == .none)
  }
}
