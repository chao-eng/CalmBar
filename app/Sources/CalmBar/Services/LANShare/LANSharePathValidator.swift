import Darwin
import Foundation

// MARK: - 已打开文件句柄（fd 级校验）

public struct LANShareOpenedFile {
    public let fd: Int32
    public let size: Int64
    public let isDirectory: Bool
    public let device: dev_t
    public let inode: ino_t

    public init(fd: Int32, size: Int64, isDirectory: Bool, device: dev_t, inode: ino_t) {
        self.fd = fd
        self.size = size
        self.isDirectory = isDirectory
        self.device = device
        self.inode = inode
    }

    public func close() {
        _ = Darwin.close(fd)
    }
}

public struct LANShareDirectoryEntry: Sendable {
    public let name: String
    public let isDirectory: Bool
    public let size: Int64

    public init(name: String, isDirectory: Bool, size: Int64) {
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
    }
}

// MARK: - 路径校验与 fd 级打开

public enum LANSharePathValidator {
    /// 清洗上传文件名：去掉路径分隔符、控制字符与首尾空格/点，保留扩展名并限制 255 字节。
    public static func sanitizeFilename(_ raw: String) -> String {
        var name = raw.replacingOccurrences(of: "\\", with: "/")
        if let last = name.split(separator: "/", omittingEmptySubsequences: true).last {
            name = String(last)
        }
        let filteredScalars = name.unicodeScalars.filter { scalar in
            if scalar.value < 0x20 || scalar.value == 0x7F { return false }
            if scalar == "/" || scalar == "\\" { return false }
            return true
        }
        name = String(String.UnicodeScalarView(filteredScalars))
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasPrefix(".") { name.removeFirst() }
        while name.hasSuffix(".") { name.removeLast() }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name == "." || name == ".." {
            name = "未命名文件"
        }
        return truncateUTF8(name, maxBytes: 255)
    }

    /// 校验 Router 传来的相对路径，只做词法检查，不做解码。
    public static func validateRelativePath(_ path: String) throws {
        guard !path.isEmpty else { return }
        guard !path.contains("\0"), !path.contains("\\") else {
            throw LANShareError.pathRejected
        }
        guard !path.hasPrefix("/") else { throw LANShareError.pathRejected }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        for component in components {
            if component.isEmpty || component == "." || component == ".." {
                throw LANShareError.pathRejected
            }
            if component.utf8.count > 255 { throw LANShareError.pathRejected }
        }
    }

    /// 打开分享根目录（已存在的目录）。
    public static func openRootDirectory(_ path: String) throws -> LANShareOpenedFile {
        let canonical = try canonicalPath(path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: canonical, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw LANShareError.itemInvalid
        }
        let fd = Darwin.open(canonical, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw LANShareError.pathRejected }
        var statInfo = stat()
        guard fstat(fd, &statInfo) == 0 else {
            _ = Darwin.close(fd)
            throw LANShareError.pathRejected
        }
        return LANShareOpenedFile(
            fd: fd,
            size: 0,
            isDirectory: true,
            device: statInfo.st_dev,
            inode: statInfo.st_ino
        )
    }

    /// 在分享根目录内打开相对路径，中间目录与最终组件均使用 O_NOFOLLOW，阻断 TOCTOU 与符号链接逃逸。
    public static func open(root: String, relativePath: String, allowDirectory: Bool = true) throws -> LANShareOpenedFile {
        try validateRelativePath(relativePath)
        let rootHandle = try openRootDirectory(root)
        var currentFD = rootHandle.fd

        let components = relativePath.split(separator: "/").map(String.init)
        guard !components.isEmpty else {
            if !allowDirectory {
                rootHandle.close()
                throw LANShareError.pathRejected
            }
            return rootHandle
        }

        for (index, component) in components.enumerated() {
            let isLast = index == components.count - 1
            // 最后一层在下载单个文件时必须是普通文件，不能带 O_DIRECTORY。
            let flags = isLast && !allowDirectory
                ? O_RDONLY | O_CLOEXEC | O_NOFOLLOW
                : O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
            let nextFD = openat(currentFD, component, flags)
            if currentFD != rootHandle.fd { _ = Darwin.close(currentFD) }
            guard nextFD >= 0 else {
                if index == 0 && currentFD == rootHandle.fd { rootHandle.close() }
                throw LANShareError.itemNotFound
            }
            currentFD = nextFD
        }

        var statInfo = stat()
        guard fstat(currentFD, &statInfo) == 0 else {
            _ = Darwin.close(currentFD)
            throw LANShareError.pathRejected
        }
        let isDirectory = (statInfo.st_mode & S_IFMT) == S_IFDIR
        if isDirectory && !allowDirectory {
            _ = Darwin.close(currentFD)
            throw LANShareError.pathRejected
        }
        if !isDirectory && (statInfo.st_mode & S_IFMT) != S_IFREG {
            _ = Darwin.close(currentFD)
            throw LANShareError.pathRejected
        }
        return LANShareOpenedFile(
            fd: currentFD,
            size: isDirectory ? 0 : Int64(statInfo.st_size),
            isDirectory: isDirectory,
            device: statInfo.st_dev,
            inode: statInfo.st_ino
        )
    }

    /// 打开单个分享文件：以父目录为根，最终组件 O_NOFOLLOW。
    public static func openFileItem(path: String) throws -> LANShareOpenedFile {
        let url = URL(fileURLWithPath: path)
        let parent = url.deletingLastPathComponent().path
        let name = url.lastPathComponent
        return try open(root: parent, relativePath: name, allowDirectory: false)
    }

    /// 读取目录项；符号链接一律跳过，避免越界读取。
    public static func listDirectory(root: String, relativePath: String) throws -> [LANShareDirectoryEntry] {
        let handle = try open(root: root, relativePath: relativePath, allowDirectory: true)
        guard handle.isDirectory else {
            handle.close()
            throw LANShareError.itemInvalid
        }
        let dirFD = dup(handle.fd)
        handle.close()
        guard dirFD >= 0, let directory = fdopendir(dirFD) else {
            if dirFD >= 0 { _ = Darwin.close(dirFD) }
            throw LANShareError.internalFailure("无法读取文件夹")
        }
        defer { closedir(directory) }

        var entries: [LANShareDirectoryEntry] = []
        while let entry = readdir(directory) {
            let name = withUnsafePointer(to: entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX) + 1) { cString in
                    String(cString: cString)
                }
            }
            if name == "." || name == ".." { continue }
            if name.hasPrefix(".calmbar-") { continue }

            var statInfo = stat()
            guard fstatat(dirFD, name, &statInfo, AT_SYMLINK_NOFOLLOW) == 0 else { continue }
            let mode = statInfo.st_mode & S_IFMT
            if mode == S_IFLNK { continue }
            if mode != S_IFDIR && mode != S_IFREG { continue }
            entries.append(
                LANShareDirectoryEntry(
                    name: name,
                    isDirectory: mode == S_IFDIR,
                    size: mode == S_IFDIR ? 0 : Int64(statInfo.st_size)
                )
            )
        }
        entries.sort { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        return entries
    }

    public static func isReadableDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && isDirectory.boolValue
            && FileManager.default.isReadableFile(atPath: path)
    }

    public static func isWritableDirectory(_ path: String) -> Bool {
        guard isReadableDirectory(path) else { return false }
        return FileManager.default.isWritableFile(atPath: path)
    }

    public static func canonicalPath(_ path: String) throws -> String {
        guard let resolved = realpath(path, nil) else { throw LANShareError.itemInvalid }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    static func truncateUTF8(_ text: String, maxBytes: Int) -> String {
        guard text.utf8.count > maxBytes else { return text }
        let url = URL(fileURLWithPath: text)
        let ext = url.pathExtension
        let suffix = ext.isEmpty ? "" : "." + ext
        var base = ext.isEmpty ? text : String(text.dropLast(suffix.count))
        while (base + suffix).utf8.count > maxBytes, !base.isEmpty {
            base.removeLast()
        }
        let result = base + suffix
        return result.isEmpty ? "未命名文件" : result
    }
}
