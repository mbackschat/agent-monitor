import Foundation

struct ReportTable {
    enum Columns {
        case compact(process: Int, agent: Int)
        case wide(process: Int, agent: Int)
    }

    let cpuWidth: Int
    let memoryWidth: Int
    private let preferredProcessWidth: Int

    init(metrics: [(cpu: Double?, memoryGB: Double?)], processNames: [String]) {
        preferredProcessWidth = max(
            "PROCESS".count, processNames.map { TextReport.safe($0).count }.max() ?? 0)
        cpuWidth = max(6, metrics.map { Self.number($0.cpu).count }.max() ?? 0)
        memoryWidth = max(5, metrics.map { Self.number($0.memoryGB).count }.max() ?? 0)
    }

    func columns(for width: Int) -> Columns {
        let prefixWidth = prefix(marker: " ", pid: "", cpu: "", memory: "").count
        let minimumProcess = 18
        let minimumAgent = 21
        let minimumLocation = "TTY / PROJECT".count
        let extra = width - prefixWidth - minimumProcess - minimumAgent - minimumLocation - 2
        guard width >= 85, extra >= 0 else {
            let available = max(0, width - prefixWidth - 1)
            let process = min(preferredProcessWidth, available / 2)
            return .compact(process: process, agent: available - process)
        }
        let process = min(preferredProcessWidth, minimumProcess + extra / 3)
        let agent = min(43, width - prefixWidth - process - minimumLocation - 2)
        return .wide(process: process, agent: agent)
    }

    func header(columns: Columns, grouped: Bool = false) -> String {
        let description: String
        if grouped {
            description = "LAUNCH SESSION / HEAVY PROCESS | heavy-process totals only"
        } else {
            switch columns {
            case .compact(let process, let agent):
                description = Self.pad("PROCESS", to: process) + " " + Self.pad("AGENT / SESSION", to: agent)
            case .wide(let process, let agent):
                description =
                    Self.pad("PROCESS", to: process) + " " + Self.pad("AGENT / SESSION", to: agent)
                    + " TTY / PROJECT"
            }
        }
        return prefix(marker: " ", pid: grouped ? "PID/#" : "PID", cpu: "CPU%", memory: "GB") + description
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
        "\(marker) \(Self.pad(pid, to: 6)) \(right(cpu, width: cpuWidth))\(cpuMarker) \(right(memory, width: memoryWidth))\(memoryMarker)  "
    }

    static func number(_ value: Double?) -> String {
        value.map { String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), $0) } ?? "?"
    }

    static func pad(_ value: String, to width: Int) -> String {
        String(value.prefix(width)).padding(toLength: width, withPad: " ", startingAt: 0)
    }

    private func right(_ value: String, width: Int) -> String {
        String(repeating: " ", count: max(0, width - value.count)) + value
    }
}
