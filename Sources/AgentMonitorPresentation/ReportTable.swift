import Foundation

struct ReportTable {
    struct Columns {
        let process: Int
        let agent: Int
        let directory: Int
    }

    let cpuWidth: Int
    let memoryWidth: Int
    private let identifierWidth: Int
    private let preferredProcessWidth: Int

    init(metrics: [(cpu: Double?, memoryGB: Double?)], processNames: [String], identifiers: [String] = []) {
        preferredProcessWidth = max(
            "PROCESS".count, processNames.map { TerminalCells.width(TextReport.safe($0)) }.max() ?? 0)
        cpuWidth = max(6, metrics.map { Self.number($0.cpu).count }.max() ?? 0)
        memoryWidth = max(5, metrics.map { Self.number($0.memoryGB).count }.max() ?? 0)
        identifierWidth = max(6, identifiers.map { TerminalCells.width($0) }.max() ?? 0)
    }

    func columns(for width: Int, leadingInset: Int = 0) -> Columns {
        let prefixWidth = prefix(marker: " ", pid: "", cpu: "", memory: "").count + leadingInset
        let available = max(0, width - prefixWidth - 2)
        let process = min(preferredProcessWidth, available / 3)
        let agent = min(43, available - process - available / 3)
        return Columns(process: process, agent: agent, directory: available - process - agent)
    }

    func header(columns: Columns, grouped: Bool = false, hasGroups: Bool = false) -> String {
        let description: String
        if grouped {
            description = "LAUNCH SESSION / PROCESS | all observed totals"
        } else {
            description =
                Self.pad("PROCESS", to: columns.process) + " "
                + Self.pad("AGENT / SESSION", to: columns.agent) + " CWD"
        }
        return prefix(marker: " ", pid: grouped || hasGroups ? "PID/#" : "PID", cpu: "CPU%", memory: "GB")
            + description
    }

    func directoryHeader(grouped: Bool) -> String {
        prefix(marker: " ", pid: grouped ? "PID/#" : "PID", cpu: "CPU%", memory: "GB") + "CWD"
    }

    func rowPrefix(
        marker: String, pid: String, cpu: Double?, memoryGB: Double?,
        heavyCPU: Bool = false, heavyMemory: Bool = false,
        partialCPU: Bool = false, partialMemory: Bool = false
    ) -> String {
        prefix(
            marker: marker, pid: pid, cpu: Self.number(cpu), memory: Self.number(memoryGB),
            cpuMarker: partialCPU ? "~" : heavyCPU ? "*" : " ",
            memoryMarker: partialMemory ? "~" : heavyMemory ? "*" : " ")
    }

    private func prefix(
        marker: String, pid: String, cpu: String, memory: String,
        cpuMarker: String = " ", memoryMarker: String = " "
    ) -> String {
        "\(marker) \(Self.pad(pid, to: identifierWidth)) \(right(cpu, width: cpuWidth))\(cpuMarker) \(right(memory, width: memoryWidth))\(memoryMarker)  "
    }

    static func number(_ value: Double?) -> String {
        value.map(ReportNumber.text) ?? "?"
    }

    static func pad(_ value: String, to width: Int) -> String {
        TerminalCells.padded(TextReport.safe(value), to: width)
    }

    private func right(_ value: String, width: Int) -> String {
        String(repeating: " ", count: max(0, width - value.count)) + value
    }
}
