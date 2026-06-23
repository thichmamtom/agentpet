import XCTest
@testable import AgentPetCore

final class PetWindowPlannerTests: XCTestCase {
    private func s(_ id: String, _ state: AgentState, project: String?) -> AgentSession {
        AgentSession(id: id, agentKind: .claude, project: project, state: state,
                     source: .hook, updatedAt: Date(timeIntervalSince1970: 0))
    }
    private let cat = ProjectPetMapping(projectPath: "/work/foo", petID: "cat")

    func testSplitOffSingleAggregateSpec() {
        let specs = PetWindowPlanner.plan(
            sessions: [s("1", .working, project: "/work/foo"), s("2", .waiting, project: "/x")],
            split: false, mappings: [cat], defaultPetID: "boba")
        XCTAssertEqual(specs.count, 1)
        XCTAssertEqual(specs[0].key, "default")
        XCTAssertEqual(specs[0].petID, "boba")
        XCTAssertEqual(specs[0].mood, .working)      // working beats waiting
        XCTAssertEqual(specs[0].count, 2)
    }

    func testSplitOffIdleWhenNothingActive() {
        let specs = PetWindowPlanner.plan(sessions: [], split: false, mappings: [], defaultPetID: "boba")
        XCTAssertEqual(specs.map(\.key), ["default"])
        XCTAssertEqual(specs[0].mood, .idle)
    }

    func testSplitOnGroupsByProjectAndResolvesPet() {
        let specs = PetWindowPlanner.plan(
            sessions: [s("1", .working, project: "/work/foo/src"),   // matches cat
                       s("2", .done, project: "/other")],            // unconfigured → default
            split: true, mappings: [cat], defaultPetID: "boba")
        let byKey = Dictionary(uniqueKeysWithValues: specs.map { ($0.key, $0) })
        XCTAssertEqual(byKey["/work/foo"]?.petID, "cat")
        XCTAssertEqual(byKey["/work/foo"]?.projectName, "foo")
        XCTAssertEqual(byKey["/other"]?.petID, "boba")          // default sprite
        XCTAssertEqual(byKey["/other"]?.mood, .done)
        XCTAssertNil(byKey["default"])                          // PA2: no idle home when projects active
    }

    func testSplitOnSubfolderSessionsCollapseToConfiguredRoot() {
        let specs = PetWindowPlanner.plan(
            sessions: [s("1", .working, project: "/work/foo/a"), s("2", .working, project: "/work/foo/b")],
            split: true, mappings: [cat], defaultPetID: "boba")
        XCTAssertEqual(specs.count, 1)
        XCTAssertEqual(specs[0].key, "/work/foo")
        XCTAssertEqual(specs[0].count, 2)
    }

    func testSplitOnNoProjectSessionsGoToDefaultBucket() {
        let specs = PetWindowPlanner.plan(
            sessions: [s("1", .working, project: nil)],
            split: true, mappings: [], defaultPetID: "boba")
        XCTAssertEqual(specs.map(\.key), ["default"])
        XCTAssertEqual(specs[0].petID, "boba")
        XCTAssertEqual(specs[0].mood, .working)
    }

    func testSplitOnIdleHomeWhenNothingActive() {
        let specs = PetWindowPlanner.plan(sessions: [], split: true, mappings: [cat], defaultPetID: "boba")
        XCTAssertEqual(specs.map(\.key), ["default"])
        XCTAssertEqual(specs[0].mood, .idle)
    }

    func testRegisteredAndIdleNotActive() {
        let specs = PetWindowPlanner.plan(
            sessions: [s("1", .idle, project: "/work/foo"), s("2", .registered, project: "/y")],
            split: true, mappings: [cat], defaultPetID: "boba")
        XCTAssertEqual(specs.map(\.key), ["default"])   // nothing active → idle home
        XCTAssertEqual(specs[0].mood, .idle)
    }
}
