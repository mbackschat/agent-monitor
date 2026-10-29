import AgentMonitorPresentation
import Foundation
import Testing

@testable import AgentMonitorCore

/// Product contract: a row must show agent/session identity, workload directory, executable and
/// contribution together (docs/product.md, "Information that belongs together").
@Suite struct SessionContributorRowsTests {
    private let alpha = "11111111-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    private var session: ContributorID { .session(provider: "codex", session: alpha, root: nil) }

    private func overview(_ workers: [OverviewFeed.Worker]) throws -> ContributorOverview {
        var feed = OverviewFeed()
        var overview = ContributorOverview()
        overview.receive(try feed.advance(workers))
        overview.receive(try feed.advance(workers))
        return overview
    }

    private func worker(
        _ executable: String, pid: Int32, cpu: Double, cwd: String? = "/work/api", runtime: Bool = false
    ) -> OverviewFeed.Worker {
        OverviewFeed.Worker(
            session: alpha, provider: .codex, executable: executable, pid: pid, cpuPerSecond: cpu, cwd: cwd,
            runtime: runtime)
    }

    @Test func workloadExecutableRolesDoNotMistakeDirectoryTextForNames() throws {
        let value = try overview([
            worker("java", pid: 1, cpu: 1, cwd: "/work/java"),
            worker("node", pid: 2, cpu: 0.5, cwd: "/work/node"),
        ])
        let node = try #require(value.nodes[session])
        let parts = value.workloadParts(for: node)
        #expect(
            parts.compactMap { part -> String? in
                if case .executable(let name) = part { return name }
                return nil
            } == ["java", "node"])
        #expect(parts.map(\.text).joined() == value.workloadContext(for: node))
        #expect(parts.contains { $0.text.contains("/work/java") })
    }

    @Test func sessionTitleLeadsWithIdentityBeforeItsDirectory() throws {
        let single = try overview([worker("cargo", pid: 1, cpu: 1)])
        #expect(single.nodes[session]?.title == "codex · 11111111 · /work/api")
        let spread = try overview([
            worker("cargo", pid: 1, cpu: 1), worker("node", pid: 2, cpu: 1, cwd: "/work/web"),
        ])
        #expect(spread.nodes[session]?.title == "codex · 11111111 · 2 dirs")
    }

    @Test func contributorsAggregateExecutableAndDirectoryWithWorkerCounts() throws {
        let value = try overview([
            worker("java", pid: 1, cpu: 0.9), worker("java", pid: 2, cpu: 0.8),
            worker("java", pid: 3, cpu: 0.5, cwd: "/work/web"), worker("rustc", pid: 4, cpu: 0.3),
        ])
        let titles = value.nodes[session]?.children.compactMap { value.nodes[$0]?.title }
        #expect(titles == ["java ×2 · /work/api", "java · /work/web", "rustc · /work/api"])
        let grouped = ContributorID.executable(parent: session, name: "java", cwd: "/work/api")
        #expect(value.nodes[grouped]?.children.compactMap { value.nodes[$0]?.process?.pid } == [1, 2])
    }

    @Test func singleDirectorySessionKeepsTheDirectoryOnTheSessionRowOnly() throws {
        let value = try overview([worker("java", pid: 1, cpu: 0.9), worker("java", pid: 2, cpu: 0.8)])
        let child = try #require(value.nodes[session]?.children.first)
        #expect(value.nodes[child]?.title == "java ×2")
    }

    @Test func adapterRecognisedRuntimeUsesItsProviderNameAndNoWorkloadDirectory() throws {
        let value = try overview([
            worker("2.1.300", pid: 1, cpu: 0.9, cwd: "/launch", runtime: true),
            worker("cargo", pid: 2, cpu: 0.5), worker("node", pid: 3, cpu: 0.4, cwd: "/work/web"),
        ])
        let titles = value.nodes[session]?.children.compactMap { value.nodes[$0]?.title }
        #expect(titles == ["codex runtime", "cargo · /work/api", "node · /work/web"])
        #expect(value.nodes[session]?.title == "codex · 11111111 · 2 dirs")
    }

    @Test func unreadableDirectoryIsItsOwnContributor() throws {
        let value = try overview([
            worker("make", pid: 1, cpu: 0.5), worker("make", pid: 2, cpu: 0.4, cwd: nil),
        ])
        let titles = value.nodes[session]?.children.compactMap { value.nodes[$0]?.title }
        #expect(titles == ["make · /work/api", "make · CWD unavailable"])
    }

    @Test(arguments: [
        (
            ["/work/alpha/project", "/tmp/alpha/project"],
            ["/work/alpha/project", "/tmp/alpha/project"]
        ),
        (
            ["/alpha/project", "/tmp/alpha/project"],
            ["/alpha/project", "…/alpha/project"]
        ),
    ])
    func contributorDirectoriesRemainDistinctWhenSuffixesMatch(
        directories: [String], labels: [String]
    ) throws {
        let value = try overview([
            worker("java", pid: 1, cpu: 0.9, cwd: directories[0]),
            worker("java", pid: 2, cpu: 0.8, cwd: directories[1]),
            worker("java", pid: 3, cpu: 0.1, cwd: nil),
        ])
        let children = try #require(value.nodes[session]?.children)
        #expect(
            children.compactMap { value.nodes[$0]?.title }
                == labels.map { "java · " + $0 } + ["java · CWD unavailable"])
        #expect(value.nodes[session]?.title == "codex · 11111111 · 2 dirs + CWD unavailable")
        for directory in directories {
            let id = ContributorID.executable(parent: session, name: "java", cwd: directory)
            #expect(value.nodes[id]?.inspectionFields.contains { $0.value == directory } == true)
        }
    }

    @Test func singleDirectorySummariesDisambiguateAcrossSessions() throws {
        let beta = "22222222-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
        var second = worker("java", pid: 2, cpu: 0.8, cwd: "/tmp/alpha/project")
        second.session = beta
        let value = try overview([
            worker("java", pid: 1, cpu: 0.9, cwd: "/work/alpha/project"), second,
        ])
        #expect(value.nodes[session]?.title == "codex · 11111111 · /work/alpha/project")
        let other = ContributorID.session(provider: "codex", session: beta, root: nil)
        #expect(value.nodes[other]?.title == "codex · 22222222 · /tmp/alpha/project")
        #expect(value.nodes[session]?.children.compactMap { value.nodes[$0]?.title } == ["java"])
        #expect(value.nodes[other]?.children.compactMap { value.nodes[$0]?.title } == ["java"])
    }

    /// The remainder row must quantify what it hides, so CPU and lifetimes stay conserved.
    @Test func longContributorListShowsTopThreeAndAQuantifiedRemainder() throws {
        var value = try overview(
            ["a", "b", "c", "d", "e", "f"].enumerated().map {
                worker($0.element, pid: Int32($0.offset + 1), cpu: 0.6 - Double($0.offset) / 10)
            })
        let children = try #require(value.nodes[session]?.children)
        let more = ContributorID.more(parent: session)
        #expect(children.prefix(3).compactMap { value.nodes[$0]?.title } == ["a", "b", "c"])
        #expect(children.last == more)
        #expect(value.nodes[more]?.title == "+3 more")
        #expect(value.nodes[more]?.stats.processes.count == 3)
        let hidden = try #require(value.nodes[more]?.stats.currentCPU)
        let shown = children.prefix(3).compactMap { value.nodes[$0]?.stats.currentCPU }.reduce(0, +)
        #expect(abs(shown + hidden - (value.nodes[session]?.stats.currentCPU ?? 0)) < 1e-9)
        value.toggle(session)
        value.toggle(more)
        #expect(value.visibleRows.compactMap { $0.node.title }.contains("f"))
    }
}
