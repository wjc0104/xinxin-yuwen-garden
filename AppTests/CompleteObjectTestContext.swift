import Foundation
import CoreFoundation
import CryptoKit
import Darwin

// Test-bundle-only bridge. The host owns validation of the MP4 grammar and all deletion.
final class CompleteObjectTestContext {
    private enum Failure: Error { case invalid }
    private struct Manifest: Equatable {
        let nonce: String
        let bytes: Int
        let sha256: String
    }
    private struct Identity: Equatable {
        let device: Int64, inode: UInt64, bytes: Int64, mode: UInt16, links: UInt64
        let modifiedSeconds: Int64, modifiedNanoseconds: Int64, changedSeconds: Int64, changedNanoseconds: Int64
        init(_ value: stat) {
            device = Int64(value.st_dev); inode = UInt64(value.st_ino); bytes = Int64(value.st_size)
            mode = UInt16(value.st_mode); links = UInt64(value.st_nlink)
            modifiedSeconds = Int64(value.st_mtimespec.tv_sec); modifiedNanoseconds = Int64(value.st_mtimespec.tv_nsec)
            changedSeconds = Int64(value.st_ctimespec.tv_sec); changedNanoseconds = Int64(value.st_ctimespec.tv_nsec)
        }
    }
    private struct Evidence: Equatable {
        let bytes: Int
        let sha256: String
        var json: [String: Any] { ["bytes": bytes, "sha256": sha256] }
    }
    private var cachesFD: Int32 = -1, namespaceFD: Int32 = -1, sourceFD: Int32 = -1
    private var cachesURL: URL?, cachesIdentity: Identity?, namespaceURL: URL?, namespaceIdentity: Identity?, manifestIdentity: Identity?, sourceIdentity: Identity?
    private var manifest: Manifest?, before: Evidence?, after: Evidence?
    private var prepared = false, writtenPNGBytes = 0
    private var writtenPNGs: Set<String> = []

    deinit {
        if sourceFD >= 0 { Darwin.close(sourceFD) }
        if namespaceFD >= 0 { Darwin.close(namespaceFD) }
        if cachesFD >= 0 { Darwin.close(cachesFD) }
    }

    func prepare(softDeadline: Double) throws -> URL {
        guard ProcessInfo.processInfo.environment["GARDEN_COMPLETE_OBJECT_SAME_BYTES"] == "1",
              namespaceFD < 0, let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            throw Failure.invalid
        }
        cachesFD = Darwin.open(caches.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard cachesFD >= 0 else { throw Failure.invalid }
        var cachesStatus = stat()
        guard Darwin.fstat(cachesFD, &cachesStatus) == 0,
              cachesStatus.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else { throw Failure.invalid }
        cachesURL = caches; cachesIdentity = Identity(cachesStatus)
        namespaceFD = Darwin.openat(cachesFD, "complete-object-control", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard namespaceFD >= 0 else { throw Failure.invalid }
        namespaceIdentity = Identity(try directoryStatus())
        namespaceURL = caches.appendingPathComponent("complete-object-control", isDirectory: true)
        try verifyNamespace()
        guard let namespaceURL = namespaceURL,
              let entries = try? FileManager.default.contentsOfDirectory(atPath: namespaceURL.path),
              Set(entries) == Set(["source.mp4", "manifest.json"]) else { throw Failure.invalid }
        let loaded = try readManifest()
        manifest = loaded.0; manifestIdentity = loaded.1
        sourceFD = Darwin.openat(namespaceFD, "source.mp4", O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard sourceFD >= 0 else { throw Failure.invalid }
        sourceIdentity = Identity(try sourceStatus())
        before = try verifySource(softDeadline: softDeadline)
        prepared = true
        return namespaceURL.appendingPathComponent("source.mp4", isDirectory: false)
    }

    func finalize(_ summary: inout [String: Any]) -> Bool {
        var verified = false
        if prepared {
            do { after = try verifySource(); verified = before == after }
            catch { verified = false }
        }
        summary["scope"] = "localCompleteObjectDecodedOutput"
        summary["nonce"] = manifest.map { $0.nonce as Any } ?? NSNull()
        summary["fileBefore"] = before.map { $0.json as Any } ?? NSNull()
        summary["fileAfter"] = after.map { $0.json as Any } ?? NSNull()
        summary["sourceHashVerified"] = verified
        summary["completed"] = (summary["captureCompleted"] as? Bool == true) &&
            (summary["artifactsSucceeded"] as? Bool == true) && verified
        if !verified { summary["stage"] = "source-validation-failed" }
        return verified
    }

    func writePNG(_ data: Data, name: String) throws {
        let leaves: Set<String> = ["plain-05.png", "plain-15.png", "plain-25.png", "plain-paused52.png"]
        guard prepared, leaves.contains(name), !writtenPNGs.contains(name), data.count <= 4 * 1024 * 1024,
              writtenPNGBytes + data.count <= 16 * 1024 * 1024 else { throw Failure.invalid }
        try writeLeaf(data, name: name)
        writtenPNGs.insert(name); writtenPNGBytes += data.count
    }

    func writeResult(_ summary: [String: Any]) throws {
        guard let data = try? JSONSerialization.data(withJSONObject: summary, options: [.sortedKeys]),
              data.count <= 16 * 1024 else { throw Failure.invalid }
        try writeLeaf(data, name: "result.json")
    }

    private func directoryStatus() throws -> stat {
        var status = stat()
        guard namespaceFD >= 0, Darwin.fstat(namespaceFD, &status) == 0,
              status.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              status.st_mode & mode_t(0o7777) == mode_t(0o700) else { throw Failure.invalid }
        return status
    }

    private func verifyNamespace() throws {
        let descriptor = try directoryStatus()
        var named = stat(), namedCaches = stat(), descriptorCaches = stat()
        guard cachesFD >= 0, let cachesURL = cachesURL, let expectedCaches = cachesIdentity,
              Darwin.fstat(cachesFD, &descriptorCaches) == 0,
              Darwin.lstat(cachesURL.path, &namedCaches) == 0,
              namedCaches.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              namedCaches.st_dev == descriptorCaches.st_dev, namedCaches.st_ino == descriptorCaches.st_ino,
              expectedCaches.device == Int64(descriptorCaches.st_dev), expectedCaches.inode == UInt64(descriptorCaches.st_ino),
              Darwin.fstatat(cachesFD, "complete-object-control", &named, AT_SYMLINK_NOFOLLOW) == 0,
              named.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              named.st_mode & mode_t(0o7777) == mode_t(0o700),
              named.st_dev == descriptor.st_dev, named.st_ino == descriptor.st_ino,
              let expected = namespaceIdentity, expected.device == Int64(descriptor.st_dev),
              expected.inode == UInt64(descriptor.st_ino) else { throw Failure.invalid }
    }

    private func sourceStatus() throws -> stat {
        var status = stat(), named = stat()
        guard sourceFD >= 0, Darwin.fstat(sourceFD, &status) == 0,
              status.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), status.st_nlink == 1,
              status.st_mode & mode_t(0o7777) == mode_t(0o400),
              status.st_size > 0, status.st_size <= 64 * 1024 * 1024,
              Darwin.fstatat(namespaceFD, "source.mp4", &named, AT_SYMLINK_NOFOLLOW) == 0,
              Identity(named) == Identity(status) else { throw Failure.invalid }
        return status
    }

    private func readManifest() throws -> (Manifest, Identity) {
        try verifyNamespace()
        let descriptor = Darwin.openat(namespaceFD, "manifest.json", O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw Failure.invalid }
        defer { Darwin.close(descriptor) }
        var status = stat(), named = stat(), ended = stat()
        guard Darwin.fstat(descriptor, &status) == 0,
              status.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), status.st_nlink == 1,
              status.st_size > 0, status.st_size <= 4096 else { throw Failure.invalid }
        var data = Data(), storage = [UInt8](repeating: 0, count: 4097)
        while true {
            let count = storage.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, $0.count) }
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw Failure.invalid }
            if count == 0 { break }
            guard data.count + count <= 4096 else { throw Failure.invalid }
            data.append(contentsOf: storage.prefix(count))
        }
        guard data.count == Int(status.st_size), Darwin.fstat(descriptor, &ended) == 0,
              Darwin.fstatat(namespaceFD, "manifest.json", &named, AT_SYMLINK_NOFOLLOW) == 0,
              Identity(status) == Identity(ended), Identity(status) == Identity(named),
              let text = String(data: data, encoding: .utf8), !text.contains("\\"),
              ["\"schema\"", "\"nonce\"", "\"bytes\"", "\"sha256\""].allSatisfy({ text.components(separatedBy: $0).count == 2 }),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              Set(object.keys) == Set(["schema", "nonce", "bytes", "sha256"]),
              integer(object["schema"]) == 1, let bytes = integer(object["bytes"]), bytes > 0,
              bytes <= 64 * 1024 * 1024, let nonce = object["nonce"] as? String, nonce.count == 36,
              UUID(uuidString: nonce)?.uuidString.lowercased() == nonce,
              let sha256 = object["sha256"] as? String, sha256.count == 64,
              sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw Failure.invalid }
        return (Manifest(nonce: nonce, bytes: bytes, sha256: sha256), Identity(status))
    }

    private func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              !["f", "d"].contains(String(cString: number.objCType)) else { return nil }
        return Int(number.stringValue)
    }

    private func verifySource(softDeadline: Double? = nil) throws -> Evidence {
        try verifyNamespace()
        let loaded = try readManifest()
        guard let manifest = manifest, loaded.0 == manifest, loaded.1 == manifestIdentity,
              let identity = sourceIdentity, Identity(try sourceStatus()) == identity,
              identity.bytes == Int64(manifest.bytes), Darwin.lseek(sourceFD, 0, SEEK_SET) == 0 else { throw Failure.invalid }
        var hash = SHA256(), total = 0
        var storage = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            if let deadline = softDeadline, ProcessInfo.processInfo.systemUptime >= deadline { throw Failure.invalid }
            let count = storage.withUnsafeMutableBytes { Darwin.read(sourceFD, $0.baseAddress, min($0.count, manifest.bytes - total + 1)) }
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw Failure.invalid }
            if count == 0 { break }
            guard total + count <= manifest.bytes, total + count <= 64 * 1024 * 1024 else { throw Failure.invalid }
            let chunk = Data(storage.prefix(count))
            hash.update(data: chunk); total += count
        }
        let sha256 = hash.finalize().map { String(format: "%02x", $0) }.joined()
        try verifyNamespace()
        guard total == manifest.bytes, sha256 == manifest.sha256,
              Identity(try sourceStatus()) == identity else { throw Failure.invalid }
        let finalManifest = try readManifest()
        guard finalManifest.0 == manifest, finalManifest.1 == manifestIdentity else { throw Failure.invalid }
        return Evidence(bytes: total, sha256: sha256)
    }

    private func writeLeaf(_ data: Data, name: String) throws {
        try verifyNamespace()
        let descriptor = Darwin.openat(namespaceFD, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard descriptor >= 0 else { throw Failure.invalid }
        defer { Darwin.close(descriptor) }
        var offset = 0
        while offset < data.count {
            let count = data.withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress!.advanced(by: offset), data.count - offset) }
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { throw Failure.invalid }
            offset += count
        }
        var status = stat(), named = stat()
        guard Darwin.fsync(descriptor) == 0, Darwin.fstat(descriptor, &status) == 0,
              status.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), status.st_nlink == 1,
              status.st_size == data.count,
              Darwin.fstatat(namespaceFD, name, &named, AT_SYMLINK_NOFOLLOW) == 0,
              Identity(named) == Identity(status) else { throw Failure.invalid }
        try verifyNamespace()
    }
}
