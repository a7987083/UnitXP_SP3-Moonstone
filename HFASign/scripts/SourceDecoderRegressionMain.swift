import Foundation

private enum ExpectedEnvelope: String {
	case plain
	case appstore
	case appstoreV2 = "appstore_v2"
}

private struct RegressionCase {
	let url: URL
	let previouslyVerifiedCount: Int
}

@main
enum SourceDecoderRegressionMain {
	static func main() async throws {
		try verifyEnvelopeDetectionFixtures()

		let cases = [
			RegressionCase(
				url: URL(string: "https://raw.githubusercontent.com/maxchang3/ani-altstore-source/main/generated/apps.json")!,
				previouslyVerifiedCount: 2
			),
			RegressionCase(
				url: URL(string: "https://sign.io31.top/appstore")!,
				previouslyVerifiedCount: 214
			),
			RegressionCase(
				url: URL(string: "https://qnq.ioswg.com/appstore")!,
				previouslyVerifiedCount: 2578
			),
			RegressionCase(
				url: URL(string: "https://yxy.ioswg.com/appstore")!,
				previouslyVerifiedCount: 1716
			),
			RegressionCase(
				url: URL(string: "https://app.zonoeios.xyz/appstore")!,
				previouslyVerifiedCount: 4889
			)
		]

		for item in cases {
			let sourceData = try await load(item.url)
			let detected = try detectEnvelope(sourceData)
			let decoded = try await QNQSourcePayloadDecoder.decode(sourceData)
			let object = try JSONSerialization.jsonObject(with: decoded, options: [.fragmentsAllowed])
			guard let root = object as? [String: Any], let apps = root["apps"] as? [Any], !apps.isEmpty else {
				throw RegressionError("\(item.url.absoluteString): decoded repository has no apps[]")
			}
			print("[source-regression] PASS envelope=\(detected.rawValue) apps=\(apps.count) prior=\(item.previouslyVerifiedCount) url=\(item.url.absoluteString)")
		}
	}

	private static func verifyEnvelopeDetectionFixtures() throws {
		let fixtures: [(String, ExpectedEnvelope)] = [
			("{\"apps\":[]}", .plain),
			("{\"appstore\":\"fixture\"}", .appstore),
			("{\"appstore_v2\":\"fixture\"}", .appstoreV2)
		]

		for (json, expected) in fixtures {
			let detected = try detectEnvelope(Data(json.utf8))
			guard detected == expected else {
				throw RegressionError("fixture envelope=\(detected.rawValue), expected=\(expected.rawValue)")
			}
		}
		print("[source-regression] PASS deterministic envelope fixtures")
	}

	private static func load(_ url: URL) async throws -> Data {
		var lastError: Error?
		for attempt in 1...3 {
			do {
				var request = URLRequest(url: url)
				request.timeoutInterval = 60
				request.cachePolicy = .reloadIgnoringLocalCacheData
				request.setValue("QNQSourceLab/0.7.2-alphaone1-regression", forHTTPHeaderField: "User-Agent")
				request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
				let (data, response) = try await URLSession.shared.data(for: request)
				guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
					throw RegressionError("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
				}
				return data
			} catch {
				lastError = error
				if attempt < 3 {
					try await Task.sleep(nanoseconds: UInt64(attempt) * 2_000_000_000)
				}
			}
		}
		throw lastError ?? RegressionError("request failed")
	}

	private static func detectEnvelope(_ data: Data) throws -> ExpectedEnvelope {
		let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
		guard let root = object as? [String: Any] else {
			return .plain
		}
		if root["appstore_v2"] is String {
			return .appstoreV2
		}
		if root["appstore"] is String {
			return .appstore
		}
		return .plain
	}
}

private struct RegressionError: LocalizedError {
	let message: String
	init(_ message: String) {
		self.message = message
	}
	var errorDescription: String? {
		message
	}
}
