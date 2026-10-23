import Foundation
import CryptoKit
import Darwin

do {
    let args = CommandLine.arguments
    guard args.count == 4,
          let key = Data(base64Encoded: args[1]),
          let signature = Data(base64Encoded: args[2]) else { throw NSError(domain: "Tempo", code: 1) }
    let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: key)
    let archive = try Data(contentsOf: URL(fileURLWithPath: args[3]))
    guard publicKey.isValidSignature(signature, for: archive) else { throw NSError(domain: "Tempo", code: 2) }
    print("Update signature verified.")
} catch {
    FileHandle.standardError.write(Data("Update signature verification failed.\n".utf8)); exit(1)
}
