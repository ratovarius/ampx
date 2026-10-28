import Foundation
import XCTest

extension XCTestCase {
    /// Records an L1 gate result. Hosted-test stdout does not reach the xcodebuild log, so results are kept
    /// as attachments. Export: `xcrun xcresulttool export attachments --path <xcresult> --output-path <dir>`.
    func emitGate(_ label: String, _ payload: some Encodable) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = (try? encoder.encode(payload)) ?? Data("{}".utf8)
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "LIBRARY-GATE-\(label)"
        attachment.lifetime = .keepAlways
        self.add(attachment)
    }
}
