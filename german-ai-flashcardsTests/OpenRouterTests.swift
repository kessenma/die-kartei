//
//  OpenRouterTests.swift
//  german-ai-flashcardsTests
//
//  Cloud pictures through the learner's OpenRouter account: the PKCE sign-in pieces, the
//  /api/v1/images request body, every response shape the probe saw (2026-10-01) mapped to a
//  picture or an error, the writer that shrinks what comes back, the prompts the cloud models
//  get, and the readiness gate every picture feature asks.
//

import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import Die_Kartei

/// A 1×1 PNG, standing in for a picture's base64.
private let tinyPNGBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="

private func json(_ string: String) -> Data { Data(string.utf8) }

@MainActor
struct OpenRouterPKCETests {
    /// RFC 7636 Appendix B.
    @Test func challengeMatchesTheRFCVector() {
        #expect(OpenRouterPKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
                == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func verifierIsFortyThreeURLSafeCharacters() {
        let verifier = OpenRouterPKCE.makeVerifier()
        #expect(verifier.count == 43)
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        #expect(verifier.unicodeScalars.allSatisfy(allowed.contains))
        #expect(OpenRouterPKCE.makeVerifier() != verifier)
    }

    @Test func authURLCarriesCallbackAndS256Challenge() throws {
        let callback = URL(string: "https://kessenma.github.io/kartei-openrouter-callback")!
        let url = OpenRouterPKCE.authURL(challenge: "abc", callback: callback)
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(url.host() == "openrouter.ai")
        #expect(url.path() == "/auth")
        #expect(query["callback_url"] == callback.absoluteString)
        #expect(query["code_challenge"] == "abc")
        #expect(query["code_challenge_method"] == "S256")
    }

    @Test func codeComesOutOfTheForwardedCallback() {
        #expect(OpenRouterPKCE.code(from: URL(string: "kartei-openrouter://callback?code=xyz-123")!) == "xyz-123")
        #expect(OpenRouterPKCE.code(from: URL(string: "kartei-openrouter://callback")!) == nil)
        #expect(OpenRouterPKCE.code(from: URL(string: "kartei-openrouter://callback?code=")!) == nil)
    }

    @Test func exchangeBodyNamesTheVerifier() throws {
        let body = try OpenRouterPKCE.exchangeBody(code: "c", verifier: "v")
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(object == ["code": "c", "code_verifier": "v", "code_challenge_method": "S256"])
    }
}

@MainActor
struct OpenRouterRequestTests {
    private func body(_ model: CloudImageModel, references: [Data] = []) throws -> [String: Any] {
        let data = try OpenRouterClient.imageRequestBody(model: model, prompt: "a cat", references: references, user: "u1")
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func bothModelsAskForASquare() throws {
        for model in CloudImageModel.allCases {
            let object = try body(model)
            #expect(object["model"] as? String == model.rawValue)
            #expect(object["prompt"] as? String == "a cat")
            #expect(object["user"] as? String == "u1")
            #expect(object["aspect_ratio"] as? String == "1:1")
            #expect(object["input_references"] == nil)
        }
    }

    @Test func referencesTravelAsDataURLsOfTheirRealType() throws {
        let png = try #require(Data(base64Encoded: tinyPNGBase64))
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0, 0, 0, 0, 0])
        let object = try body(.nanoBanana, references: [jpeg, png])
        let refs = try #require(object["input_references"] as? [[String: Any]])
        #expect(refs.count == 2)
        let first = try #require((refs[0]["image_url"] as? [String: String])?["url"])
        #expect(first.hasPrefix("data:image/jpeg;base64,"))
        let second = try #require((refs[1]["image_url"] as? [String: String])?["url"])
        #expect(second.hasPrefix("data:image/png;base64,"))
    }

    @Test func referencesAreTrimmedToWhatTheModelTakes() throws {
        let png = try #require(Data(base64Encoded: tinyPNGBase64))
        let object = try body(.museImage, references: [png, png, png])
        let refs = try #require(object["input_references"] as? [[String: Any]])
        #expect(refs.count == CloudImageModel.museImage.maxReferences)
    }

    @Test func mediaTypeIsSniffedFromTheBytes() {
        #expect(OpenRouterClient.mediaType(of: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])) == "image/png")
        #expect(OpenRouterClient.mediaType(of: Data([0xFF, 0xD8, 0xFF, 0xDB])) == "image/jpeg")
        let webp = Data("RIFF".utf8) + Data([0, 0, 0, 0]) + Data("WEBP".utf8)
        #expect(OpenRouterClient.mediaType(of: webp) == "image/webp")
    }
}

@MainActor
struct OpenRouterResponseTests {
    /// The shape `POST /api/v1/images` returned for both models in the probe.
    @Test func successYieldsTheBytesAndTheCost() throws {
        let body = json(#"""
        {"created":0,"data":[{"b64_json":"\#(tinyPNGBase64)","media_type":"image/png"}],
         "usage":{"prompt_tokens":53,"completion_tokens":1290,"cost":0.0387159}}
        """#)
        let parsed = try OpenRouterClient.parseImageResponse(body, status: 200, retryAfter: nil)
        #expect(parsed.bytes == Data(base64Encoded: tinyPNGBase64))
        #expect(parsed.mediaType == "image/png")
        #expect(parsed.cost == 0.0387159)
    }

    @Test func dataURLAndHTTPSVariantsAreAccepted() throws {
        let dataURL = json(#"{"data":[{"url":"data:image/webp;base64,\#(tinyPNGBase64)"}]}"#)
        #expect(try OpenRouterClient.parseImageResponse(dataURL, status: 200, retryAfter: nil).bytes != nil)
        let remote = json(#"{"data":[{"url":"https://cdn.example.com/p.png"}]}"#)
        #expect(try OpenRouterClient.parseImageResponse(remote, status: 200, retryAfter: nil).remoteURL
                == URL(string: "https://cdn.example.com/p.png"))
    }

    @Test func emptyDataIsNoImage() {
        #expect(throws: OpenRouterError.noImage) {
            try OpenRouterClient.parseImageResponse(json(#"{"data":[]}"#), status: 200, retryAfter: nil)
        }
    }

    @Test func badKey() {
        let body = json(#"{"error":{"message":"User not found.","code":401}}"#)
        #expect(throws: OpenRouterError.unauthorized) {
            try OpenRouterClient.parseImageResponse(body, status: 401, retryAfter: nil)
        }
    }

    /// Muse before the account owner ticks the 18+ box on its model page (probe, 2026-10-01).
    @Test func missingAgeConfirmation() {
        let body = json(#"""
        {"error":{"message":"This model requires you to complete the following before use: 18+ age confirmation.",
         "code":403,"metadata":{"missing_attestation_types":["age_18plus"],"failed_routing_step":"Gate Endpoints with Attestations"}}}
        """#)
        #expect(throws: OpenRouterError.needsAgeConfirmation) {
            try OpenRouterClient.parseImageResponse(body, status: 403, retryAfter: nil)
        }
    }

    @Test func outOfCreditKnowsWhichLimit() {
        let keyLimit = json(#"{"error":{"code":402,"message":"limit","metadata":{"limit_source":"openrouter_key_limit"}}}"#)
        #expect(OpenRouterClient.error(from: keyLimit, status: 402, retryAfter: nil) == .outOfCredit(keyLimit: true))
        let account = json(#"{"error":{"code":402,"message":"credits","metadata":{"limit_source":"openrouter_credits"}}}"#)
        #expect(OpenRouterClient.error(from: account, status: 402, retryAfter: nil) == .outOfCredit(keyLimit: false))
    }

    @Test func geminiSafetyBlockIsARefusal() {
        let body = json(#"""
        {"error":{"message":"Gemini blocked this request through content moderation.","code":400,
         "metadata":{"provider_name":"Google AI Studio","finish_reason":"PROHIBITED_CONTENT","block_reason":"PROHIBITED_CONTENT"}}}
        """#)
        #expect(OpenRouterClient.error(from: body, status: 400, retryAfter: nil) == .refused(nil))
    }

    @Test func rateLimitKeepsRetryAfter() {
        let body = json(#"{"error":{"code":429,"message":"slow down"}}"#)
        #expect(OpenRouterClient.error(from: body, status: 429, retryAfter: "7") == .rateLimited(retryAfter: 7))
    }

    /// What Muse answered on chat completions before the switch to /images.
    @Test func wrongEndpointIsAProviderError() {
        let body = json(#"{"error":{"message":"meta/muse-image is an image generation model and cannot be used with the chat/completions endpoint.","code":404}}"#)
        guard case .provider(let code, _) = OpenRouterClient.error(from: body, status: 404, retryAfter: nil) else {
            Issue.record("expected a provider error"); return
        }
        #expect(code == 404)
    }

    @Test func whichFailuresStopTheRun() {
        #expect(OpenRouterError.unauthorized.stopsRun)
        #expect(OpenRouterError.outOfCredit(keyLimit: false).stopsRun)
        #expect(OpenRouterError.needsAgeConfirmation.stopsRun)
        #expect(OpenRouterError.notConnected.stopsRun)
        #expect(!OpenRouterError.refused(nil).stopsRun)
        #expect(!OpenRouterError.noImage.stopsRun)
        #expect(!OpenRouterError.provider(code: 502, message: "").stopsRun)
        #expect(OpenRouterError.provider(code: 502, message: "").isRetryable)
        #expect(!OpenRouterError.provider(code: 404, message: "").isRetryable)
    }

    @Test func keyInfoDecodesTheProbeShape() throws {
        struct Envelope: Decodable { let data: OpenRouterClient.KeyInfo }
        let body = json(#"{"data":{"label":"sk-or-v1-abc...","usage":0.2331753,"limit":100,"limit_remaining":99.7668247,"is_free_tier":false}}"#)
        let info = try JSONDecoder().decode(Envelope.self, from: body).data
        #expect(info.usage == 0.2331753)
        #expect(info.limitRemaining == 99.7668247)
    }

    @Test func maskedKeyShowsOnlyTheEnds() {
        #expect(OpenRouterAccount.mask("sk-or-v1-0123456789abcdef") == "sk-or-v1-…cdef")
        #expect(OpenRouterAccount.mask("short") == "••••")
    }
}

@MainActor
struct CloudPictureWriterTests {
    private func squarePNG(side: Int) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    @Test func shrinksToTheLongEdgeAndWritesPNG() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cloud-writer-\(UUID()).png")
        defer { try? FileManager.default.removeItem(at: url) }
        let image = try CloudPictureWriter.write(try squarePNG(side: 1024), maxPixel: 512, to: url)
        #expect(image.width == 512 && image.height == 512)
        let written = try Data(contentsOf: url)
        #expect(OpenRouterClient.mediaType(of: written) == "image/png")
    }

    @Test func neverEnlarges() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cloud-writer-\(UUID()).png")
        defer { try? FileManager.default.removeItem(at: url) }
        let image = try CloudPictureWriter.write(try squarePNG(side: 300), maxPixel: 768, to: url)
        #expect(image.width == 300)
    }

    @Test func garbageIsUndecodable() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cloud-writer-\(UUID()).png")
        #expect(throws: CloudPictureWriter.WriteError.self) {
            try CloudPictureWriter.write(Data("not a picture".utf8), maxPixel: 512, to: url)
        }
    }
}

@MainActor
struct CloudPromptTests {
    @Test func cardPromptIsSentencesWithTheNoTextClause() {
        let prompt = CardIllustrationPrompts.cloudPrompt(
            englishTranslation: "the membership card", wordType: "noun", style: .flatIcon, detail: .justTheWord
        )
        #expect(prompt.contains("a single membership card"))
        #expect(prompt.contains(CardImageStyle.flatIcon.promptFragment))
        #expect(prompt.contains(CardIllustrationPrompts.noTextClause))
        // The negative keyword list stays an on-device thing.
        #expect(!prompt.contains("jpeg artifacts"))
    }

    @Test func requestCarriesBothHalves() {
        let request = CardIllustrationPrompts.request(englishTranslation: "to run", wordType: "verb", style: .cartoon, detail: .littleScene)
        #expect(request.sdPrompt.contains("a person performing the action: run"))
        #expect(request.sdNegative.contains("caption"))
        #expect(request.cloudPrompt.contains("a person performing the action: run"))
        #expect(request.maxPixel == CloudPictureWriter.cardMaxPixel)
    }

    @Test func storyPromptListsOnlyTheCastInTheScene() {
        let cast = [
            StoryCastMember(tag: "pigeon", look: "plump gray pigeon with a coral-orange beak"),
            StoryCastMember(tag: "baker", look: "young baker with curly red hair"),
        ]
        let prompt = StoryIllustrationPrompts.cloudPrompt(
            scene: "the pigeon steals a pretzel from the windowsill", genre: .alltag, cast: cast, hasReference: true
        )
        #expect(prompt.contains("pigeon = plump gray pigeon with a coral-orange beak"))
        #expect(!prompt.contains("curly red hair"))
        #expect(prompt.contains("consistent with the reference picture"))
        #expect(prompt.contains(StoryGenre.alltag.sdStyleSuffix))
        #expect(prompt.contains(CardIllustrationPrompts.noTextClause))
    }

    @Test func firstStoryPictureHasNoReferenceLine() {
        let prompt = StoryIllustrationPrompts.cloudPrompt(scene: "a quiet street", genre: .krimi)
        #expect(!prompt.contains("reference"))
    }
}

/// Mutates the app's own UserDefaults, so each test puts back what it found.
@MainActor
struct PictureEngineTests {
    private func withDefaults(source: PictureSource, hasKey: Bool, _ body: () -> Void) {
        let defaults = UserDefaults.standard
        let savedSource = defaults.object(forKey: PictureSource.defaultsKey)
        let savedKey = defaults.object(forKey: OpenRouterAccount.hasKeyDefaultsKey)
        defer {
            defaults.set(savedSource, forKey: PictureSource.defaultsKey)
            defaults.set(savedKey, forKey: OpenRouterAccount.hasKeyDefaultsKey)
        }
        PictureSource.current = source
        defaults.set(hasKey, forKey: OpenRouterAccount.hasKeyDefaultsKey)
        body()
    }

    @Test func cloudIsReadyExactlyWhenAKeyIsStored() {
        withDefaults(source: .cloud, hasKey: true) {
            #expect(PictureEngine.isReady)
            #expect(PictureEngine.drawnWherePhrase.contains("cloud"))
        }
        withDefaults(source: .cloud, hasKey: false) {
            #expect(!PictureEngine.isReady)
            #expect(PictureEngine.notReadyMessage.contains("OpenRouter"))
        }
    }

    @Test func onDeviceReadinessIgnoresTheKey() {
        withDefaults(source: .onDevice, hasKey: true) {
            #expect(PictureEngine.isReady == ImageGenModel.current.isDownloaded)
        }
    }

    @Test func sourceDefaultsToOnDevice() {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: PictureSource.defaultsKey)
        defer { defaults.set(saved, forKey: PictureSource.defaultsKey) }
        defaults.removeObject(forKey: PictureSource.defaultsKey)
        #expect(PictureSource.current == .onDevice)
    }
}

@MainActor
struct PictureRunReportTests {
    @Test func eachStoppingErrorOffersItsFix() {
        #expect(OpenRouterError.outOfCredit(keyLimit: false).reportFix == .addCredit)
        #expect(OpenRouterError.outOfCredit(keyLimit: true).reportFix == .raiseKeyLimit)
        #expect(OpenRouterError.needsAgeConfirmation.reportFix == .confirmAge)
        #expect(OpenRouterError.unauthorized.reportFix == .reconnect)
        #expect(OpenRouterError.notConnected.reportFix == .reconnect)
        #expect(OpenRouterError.refused(nil).reportFix == nil)
    }

    @Test func onlyRunsThatWentWrongAreWorthShowing() {
        #expect(!PictureRunReport(drawn: 20, total: 20, skipped: 0).isWorthShowing)
        #expect(PictureRunReport(drawn: 18, total: 20, skipped: 2).isWorthShowing)
        #expect(PictureRunReport(drawn: 5, total: 20, skipped: 0, stopReason: "No credit", fix: .addCredit).isWorthShowing)
    }

    @Test func aCleanRunClearsTheOldReport() {
        let id = UUID()
        let store = PictureRunReports.shared
        defer { store.clear(id) }
        store.record(PictureRunReport(drawn: 5, total: 20, skipped: 0, stopReason: "No credit", fix: .addCredit), for: id)
        #expect(store.report(for: id)?.fix == .addCredit)
        store.record(PictureRunReport(drawn: 15, total: 15, skipped: 0), for: id)
        #expect(store.report(for: id) == nil)
    }

    @Test func dismissingForgetsIt() {
        let id = UUID()
        let store = PictureRunReports.shared
        store.record(PictureRunReport(drawn: 3, total: 4, skipped: 1), for: id)
        #expect(store.report(for: id) != nil)
        store.clear(id)
        #expect(store.report(for: id) == nil)
    }
}

@MainActor
struct PictureRunReasonTests {
    /// The banner's button carries the fix, so its reason doesn't repeat the instructions.
    @Test func reportReasonsLeaveTheFixToTheButton() {
        for error in [OpenRouterError.outOfCredit(keyLimit: false), .outOfCredit(keyLimit: true),
                      .needsAgeConfirmation, .unauthorized, .notConnected] {
            #expect(!error.reportReason.contains("Settings"))
            #expect(!error.reportReason.contains("openrouter.ai/"))
        }
    }
}
