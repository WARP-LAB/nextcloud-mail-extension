import Foundation

/// What the send flow asks of Nextcloud, so that tests can run it without a server.
protocol NextcloudService {
    func sharingLimits() async throws -> SharingLimits
    func createFolders(_ path: String) async throws
    func createUniqueFolder(named name: String, in directory: String) async throws -> String
    func upload(_ file: URL, to path: String) async throws
    func share(_ path: String, expireDate: String, password: String?) async throws -> Share
    func setPassword(_ password: String, forShare id: String) async throws
    func delete(_ path: String) async throws
}

extension NextcloudClient: NextcloudService {}

/// Why a send stopped. Mail shows the text in an alert with only an OK button, and keeps the message window open
/// with its files (docs/MAIL.md).
struct SendError: Error, Equatable, LocalizedError {
    let errorDescription: String?

    init(_ text: String) {
        errorDescription = text
    }

    static let notSetUp = SendError(
        "NextcloudAppleMail isn't set up, so the files can't become links. Log in to Nextcloud in the "
            + "NextcloudAppleMail app, or turn off Sign to send the files attached.")
    static let passwordRequired = SendError(
        "Your Nextcloud server requires a password on links. Set one with NextcloudAppleMail's button in the "
            + "message window's toolbar, then send again.")

    static func file(_ name: String, _ error: Error) -> SendError {
        SendError("NextcloudAppleMail couldn't upload or share “\(name)”. \(error.localizedDescription)")
    }

    static func folder(_ error: Error) -> SendError {
        SendError("NextcloudAppleMail couldn't create or share the email's folder. \(error.localizedDescription)")
    }

    static func password(_ error: Error) -> SendError {
        SendError("NextcloudAppleMail couldn't change the links' password. \(error.localizedDescription)")
    }
}

/// What the send flow reports while it uploads, for the progress notification (R3).
enum SendProgress: Equatable {
    /// Uploads start of files that aren't on Nextcloud yet.
    case uploading(files: Int, bytes: Int)
    case uploaded(files: Int, bytes: Int)
    case failed
}

/// A message's ledger entry, changed as each folder, upload and share is done, so that a failure part way keeps
/// what's done for the retry.
final class MessageRecord {
    var entry: UploadLedger.Entry

    init(_ entry: UploadLedger.Entry) {
        self.entry = entry
    }
}

/// Uploads and shares a message's files, and rewrites the message with their links (FR1, FR4, FR7–FR9, D17).
struct SendFlow {
    /// The expiry date and password every share of the message gets.
    struct LinkOptions {
        var expireDate: String
        var password: String?
    }

    var settings: Settings
    var service: NextcloudService
    var today = Date()
    var temporaryDirectory = FileManager.default.temporaryDirectory
    /// Told when uploads start and end, but not for a call that finds every file uploaded already.
    var progress: (SendProgress) -> Void = { _ in }

    /// The message with links in place of `files`. Files already in `record` are reused, not uploaded again.
    ///
    /// - Parameter applied: the password this process last gave the record's shares, "" for none, or nil when it
    ///   doesn't know, as after Mail restarted. Shares made earlier are brought to `password` when it differs.
    func run(
        _ message: MimeMessage, files: [MessageFile], password: String?, applied: String? = nil, record: MessageRecord
    ) async throws -> Data {
        let password = password.flatMap { $0.isEmpty ? nil : $0 }
        let limits = try await service.sharingLimits()
        if limits.passwordEnforced && password == nil {
            throw SendError.passwordRequired
        }
        try await updatePasswords(to: password, applied: applied, record)
        let expireDate = settings.expiry.expireDate(from: today, limits: limits)
        let options = LinkOptions(expireDate: expireDate, password: password)
        let folder = try await folder(for: message, record)
        let eachFile = settings.sharing == .eachFile
        let stored = try await putAll(files, in: folder, share: eachFile ? options : nil, record)
        let allFilesLinks = settings.onlyFolderLinks || (settings.folderLinks && files.count >= 2)
        let folderShare = !eachFile || allFilesLinks ? try await share(folder, options, record) : nil
        var links: [Int: LinkedFile] = [:]
        for file in files {
            guard let item = stored[file.index] else {
                continue
            }
            links[file.index] = Self.linked(file, item, folderShare: eachFile ? nil : folderShare)
        }
        let folderLinks =
            allFilesLinks ? folderShare.map { FolderLinks(viewURL: $0.url, downloadURL: $0.downloadURL) } : nil
        record.entry.passwordProtected = password != nil
        var rewriter = LinkRewriter(text: LinkText(style: settings.linkStyle))
        rewriter.linksInPlace = !settings.onlyFolderLinks
        return rewriter.rewrite(message, links: links, folder: folderLinks, passwordNotice: password != nil)
    }

    /// Deletes the message's folder, which deletes its files and shares too (FR10, D8).
    func removeUploads(_ entry: UploadLedger.Entry) async throws {
        guard let folder = entry.folder else {
            return
        }
        do {
            try await service.delete(folder)
        } catch NextcloudError.notFound {
            return
        }
    }

    // MARK: - Steps

    /// Gives the shares made in an earlier call the email's current password, as after Undo Send with another
    /// password, or none. Nothing changes when the shares already have it.
    private func updatePasswords(to password: String?, applied: String?, _ record: MessageRecord) async throws {
        let wanted = password ?? ""
        if let applied, applied == wanted {
            return
        }
        if applied == nil && password == nil && !record.entry.passwordProtected {
            return
        }
        var ids = [record.entry.folderShare?.id].compactMap { $0 }
        ids += record.entry.files.values.compactMap(\.share?.id)
        do {
            for id in Set(ids).sorted() {
                try await service.setPassword(wanted, forShare: id)
            }
        } catch {
            throw SendError.password(error)
        }
        record.entry.passwordProtected = password != nil
    }

    private func folder(for message: MimeMessage, _ record: MessageRecord) async throws -> String {
        if let folder = record.entry.folder {
            return folder
        }
        let subject = message.root.field("subject").map(EncodedWords.decode)
        do {
            try await service.createFolders(settings.uploadDirectory)
            let folder = try await service.createUniqueFolder(
                named: NextcloudNames.folder(date: today, subject: subject), in: settings.uploadDirectory)
            record.entry.folder = folder
            return folder
        } catch {
            throw SendError.folder(error)
        }
    }

    /// Uploads and shares the files the record doesn't have yet, telling `progress` when that starts and ends.
    private func putAll(
        _ files: [MessageFile], in folder: String, share options: LinkOptions?, _ record: MessageRecord
    ) async throws -> [Int: UploadLedger.StoredFile] {
        var pending: [String: Int] = [:]
        for file in files where record.entry.files[UploadLedger.key(for: file.data)] == nil {
            pending[UploadLedger.key(for: file.data)] = file.decodedSize
        }
        let count = pending.count
        let bytes = pending.values.reduce(0, +)
        if count > 0 {
            progress(.uploading(files: count, bytes: bytes))
        }
        let eachFile = options != nil
        let names = files.map { eachFile ? $0.filename : NextcloudNames.folderShareName($0.filename) }
        var stored: [Int: UploadLedger.StoredFile] = [:]
        for (file, name) in zip(files, NextcloudNames.uniqueFiles(names)) {
            do {
                stored[file.index] = try await put(file, named: name, in: folder, share: options, record)
            } catch {
                if count > 0 {
                    progress(.failed)
                }
                throw SendError.file(file.filename, error)
            }
        }
        if count > 0 {
            progress(.uploaded(files: count, bytes: bytes))
        }
        return stored
    }

    /// Uploads the file, and shares it when each file gets a link, unless the record has it already.
    private func put(
        _ file: MessageFile, named name: String, in folder: String, share options: LinkOptions?,
        _ record: MessageRecord
    ) async throws -> UploadLedger.StoredFile {
        let data = file.data
        let key = UploadLedger.key(for: data)
        var stored: UploadLedger.StoredFile
        if let existing = record.entry.files[key] {
            stored = existing
        } else {
            stored = UploadLedger.StoredFile(path: try await upload(data, named: name, in: folder))
            record.entry.files[key] = stored
        }
        if let options, stored.share == nil {
            stored.share = try await service.share(
                stored.path, expireDate: options.expireDate, password: options.password)
            record.entry.files[key] = stored
        }
        return stored
    }

    /// Uploads from a temporary file (R5), as `name (2)` and so on if the name is taken, and returns the path.
    private func upload(_ data: Data, named name: String, in folder: String) async throws -> String {
        let temporary = temporaryDirectory.appendingPathComponent("ncam-\(UUID().uuidString)")
        try data.write(to: temporary)
        defer {
            try? FileManager.default.removeItem(at: temporary)
        }
        for number in 1...100 {
            let path = NextcloudClient.join(folder, number == 1 ? name : NextcloudNames.numbered(name, number))
            do {
                try await service.upload(temporary, to: path)
                return path
            } catch NextcloudError.exists {
                continue
            }
        }
        throw NextcloudError.exists(NextcloudClient.join(folder, name))
    }

    private func share(_ folder: String, _ options: LinkOptions, _ record: MessageRecord) async throws -> Share {
        if let share = record.entry.folderShare {
            return share
        }
        do {
            let share = try await service.share(folder, expireDate: options.expireDate, password: options.password)
            record.entry.folderShare = share
            return share
        } catch {
            throw SendError.folder(error)
        }
    }

    // MARK: - Links

    /// A file's links: its own share's, or with the folder shared, the folder's page and a download of the file.
    static func linked(_ file: MessageFile, _ stored: UploadLedger.StoredFile, folderShare: Share?) -> LinkedFile {
        let share = folderShare ?? stored.share
        let view = share?.url ?? URL(fileURLWithPath: "/")
        let download = folderShare.map { downloadURL(of: stored.name, in: $0) } ?? share?.downloadURL ?? view
        return LinkedFile(
            filename: stored.name, size: file.decodedSize, viewURL: view, downloadURL: download,
            expiry: share?.expiration)
    }

    /// The folder share's download of one file, `/s/<token>/download?files=<name>` (docs/NEXTCLOUD.md).
    static func downloadURL(of name: String, in share: Share) -> URL {
        var components = URLComponents(url: share.downloadURL, resolvingAgainstBaseURL: false)
        components?.percentEncodedQuery = "files=" + NextcloudClient.encode(name)
        return components?.url ?? share.downloadURL
    }
}
