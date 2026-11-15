//
//  ChallengeCardNFC.swift
//  Beastopia
//

import CoreNFC
import Foundation

/// Reads and writes Challenge Cards on NFC stickers and cards (NTAG215/216 or any writable
/// NDEF tag). iPhones can't talk to each other over NFC, so a tag carries the challenge instead:
/// write your fighter to a sticker, and anyone who taps it fights your beast's ghost.
final class ChallengeCardNFC: NSObject, NFCNDEFReaderSessionDelegate {
    enum NFCError: LocalizedError {
        case unavailable
        case notACard
        case cancelled
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .unavailable: "This device can't read NFC tags."
            case .notACard: "That tag doesn't hold a Beastopia Challenge Card."
            case .cancelled: nil
            case .failed(let message): message
            }
        }
    }

    private enum Job {
        case read
        case write(String)
    }

    /// NFC Tag Reading needs a paid Apple Developer Program team: personal teams can't sign the
    /// `com.apple.developer.nfc.readersession.formats` entitlement. To turn NFC cards on, add that
    /// entitlement (value `TAG`) to Beastopia.entitlements and set this to `true`. Until then the
    /// NFC buttons stay hidden and QR Challenge Cards do the same job.
    static let isEntitled = false

    static var isAvailable: Bool { isEntitled && NFCNDEFReaderSession.readingAvailable }

    private var session: NFCNDEFReaderSession?
    private var job: Job = .read
    private var continuation: CheckedContinuation<String, Error>?

    /// Waits for the keeper to tap a tag, then returns the card text on it.
    func read() async throws -> String {
        try await run(.read, prompt: "Hold your iPhone near a Challenge Card.")
    }

    /// Waits for the keeper to tap a writable tag, then writes the card to it.
    func write(_ card: ChallengeCard) async throws {
        _ = try await run(.write(card.payload), prompt: "Hold your iPhone near a blank NFC sticker or card.")
    }

    private func run(_ job: Job, prompt: String) async throws -> String {
        guard Self.isAvailable else { throw NFCError.unavailable }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation?.resume(throwing: NFCError.cancelled)
            self.continuation = continuation
            self.job = job
            let session = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: false)
            session.alertMessage = prompt
            self.session = session
            session.begin()
        }
    }

    private func finish(_ result: Result<String, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }

    // MARK: - NFCNDEFReaderSessionDelegate

    nonisolated func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {}

    nonisolated func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        let code = (error as? NFCReaderError)?.code
        let message = error.localizedDescription
        Task { @MainActor in
            // Closing the sheet, or the session ending after success, isn't a failure.
            if code == .readerSessionInvalidationErrorUserCanceled || code == .readerSessionInvalidationErrorFirstNDEFTagRead {
                self.finish(.failure(NFCError.cancelled))
            } else {
                self.finish(.failure(NFCError.failed(message)))
            }
        }
    }

    nonisolated func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]) {
        nonisolated(unsafe) let session = session
        guard let tag = tags.first else { return }
        nonisolated(unsafe) let unsafeTag = tag
        Task { @MainActor in
            let job = self.job
            do {
                try await session.connect(to: unsafeTag)
                let (status, _) = try await unsafeTag.queryNDEFStatus()
                switch job {
                case .read:
                    let message = try await unsafeTag.readNDEF()
                    let texts = message.records.compactMap { $0.wellKnownTypeTextPayload().0 }
                    guard let card = texts.first(where: ChallengeCard.isCard) else {
                        session.invalidate(errorMessage: NFCError.notACard.errorDescription ?? "")
                        self.finish(.failure(NFCError.notACard))
                        return
                    }
                    session.alertMessage = "Challenge accepted!"
                    session.invalidate()
                    self.finish(.success(card))
                case .write(let payload):
                    guard status == .readWrite,
                          let record = NFCNDEFPayload.wellKnownTypeTextPayload(string: payload, locale: Locale(identifier: "en")) else {
                        let reason = "This tag can't be written to."
                        session.invalidate(errorMessage: reason)
                        self.finish(.failure(NFCError.failed(reason)))
                        return
                    }
                    try await unsafeTag.writeNDEF(NFCNDEFMessage(records: [record]))
                    session.alertMessage = "Challenge Card written!"
                    session.invalidate()
                    self.finish(.success(payload))
                }
            } catch {
                session.invalidate(errorMessage: "Couldn't use that tag. Try again.")
                self.finish(.failure(NFCError.failed(error.localizedDescription)))
            }
        }
    }
}
