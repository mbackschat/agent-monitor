import CoreML
import Dispatch
import Vision

private func nativeTextRecognitionRequest() throws -> VNRecognizeTextRequest {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    // Headless render checks use CPU devices to avoid accelerator waits (docs/development.md).
    for (stage, devices) in try request.supportedComputeStageDevices {
        guard
            let cpu = devices.first(where: { device in
                if case .cpu = device { return true }
                return false
            })
        else { throw NativeTextRecognitionFailure.cpuDeviceUnavailable(String(describing: stage)) }
        request.setComputeDevice(cpu, for: stage)
    }
    return request
}

struct NativeRecognizedText: Sendable {
    let text: String
    let bounds: CGRect
}

private let recognitionQueue = DispatchQueue(label: "agent-monitor.tests.text-recognition")

func nativeRecognizedText(in image: CGImage) async throws -> [NativeRecognizedText] {
    try Task.checkCancellation()
    // The 2026-10-29 stack in docs/research/native-menu-design.md shows blocking Vision OCR
    // starving MainActor. A dedicated queue keeps it off UI and cooperative executor threads.
    let result: [NativeRecognizedText] = try await withCheckedThrowingContinuation { continuation in
        recognitionQueue.async {
            do {
                let request = try nativeTextRecognitionRequest()
                try VNImageRequestHandler(cgImage: image).perform([request])
                let result = (request.results ?? []).compactMap { observation in
                    observation.topCandidates(1).first.map {
                        NativeRecognizedText(text: $0.string, bounds: observation.boundingBox)
                    }
                }
                continuation.resume(returning: result)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    try Task.checkCancellation()
    return result
}

private enum NativeTextRecognitionFailure: Error {
    case cpuDeviceUnavailable(String)
}
