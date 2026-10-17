public struct DiagnosisReportSection: Equatable, Sendable {
    public enum Kind: Sendable { case summary, contributor, notes }
    public let kind: Kind
    public let title: String
    public internal(set) var lines: [ReportLine]

    init(kind: Kind, title: String, lines: [ReportLine]) {
        self.kind = kind
        self.title = TextReport.safe(title)
        self.lines = lines
    }

    static func displayLines(_ sections: [Self]) -> [ReportLine] {
        sections.enumerated().flatMap { index, section in
            (index == 0 ? [] : [ReportLine("")])
                + [ReportLine(section.title, style: .heading)] + section.lines
        }
    }
}
