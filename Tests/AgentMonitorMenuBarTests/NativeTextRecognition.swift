import CoreML
import Testing
import Vision

func nativeTextRecognitionRequest() throws -> VNRecognizeTextRequest {
    // The session-heading render guard stalled in Vision's default device scheduler on 2026-10-27;
    // CPU stages keep this image oracle independent of GPU and Neural Engine service scheduling.
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    // Headless render checks use CPU devices to avoid accelerator waits (docs/development.md).
    for (stage, devices) in try request.supportedComputeStageDevices {
        let cpu = try #require(
            devices.first { device in
                if case .cpu = device { return true }
                return false
            }, "Offscreen text recognition requires CPU support for \(stage)")
        request.setComputeDevice(cpu, for: stage)
    }
    return request
}
