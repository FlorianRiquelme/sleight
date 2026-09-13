import Vision
import CoreMedia

typealias Joint = VNHumanHandPoseObservation.JointName

/// One detected hand: normalized landmark positions (origin bottom-left, 0...1).
struct Hand {
    let chirality: VNChirality
    let points: [Joint: CGPoint]
    let confidence: Float

    subscript(_ j: Joint) -> CGPoint? { points[j] }
}

final class HandPoseDetector {
    private let request: VNDetectHumanHandPoseRequest = {
        let r = VNDetectHumanHandPoseRequest()
        r.maximumHandCount = 1
        return r
    }()
    var minJointConfidence: Float = 0.3

    func detect(_ buffer: CMSampleBuffer) -> Hand? {
        let handler = VNImageRequestHandler(cmSampleBuffer: buffer, orientation: .up, options: [:])
        do { try handler.perform([request]) } catch { return nil }
        guard let obs = request.results?.first,
              let all = try? obs.recognizedPoints(.all) else { return nil }
        var pts: [Joint: CGPoint] = [:]
        for (joint, p) in all where p.confidence >= minJointConfidence {
            pts[joint] = p.location
        }
        return Hand(chirality: obs.chirality, points: pts, confidence: obs.confidence)
    }
}
