// Copyright (c) 2022 Timofey Solomko
// Licensed under MIT License
//
// See LICENSE for license information

import Foundation
import BitByteData

/// Provides access to entries and contents in a zip file
class ZipUtil {

    public static func writeEntryData(_ data: Data, _ helper: ZipEntryInfoHelper, toUrl outputUrl: URL) throws {
        // TODO Support types other than .copy
        // TODO Size and crc check
        
        // Check if the directory exists
        let fm = FileManager.default
        let isDir = helper.entryInfo.type == .directory
        let pathUrl = isDir ? outputUrl : outputUrl.deletingLastPathComponent()
        if !fm.fileExists(atPath: pathUrl.path) {
            try fm.createDirectory(at: pathUrl, withIntermediateDirectories: true)
        }
        if isDir {
            // No file to create
            return
        }
        
        // Make sure we can handle the compression
        if helper.entryInfo.compressionMethod != .copy {
            throw ZipError.compressionNotSupported
        }

        // Write out the file, copy (store) only for now
        try data[helper.dataOffset..<(helper.dataOffset + Int(helper.uncompSize))].write(to: outputUrl)
    }
    
    public static func getEntryData(_ data: Data, _ helper: ZipEntryInfoHelper) throws -> (data: Data, crcError: Bool) {
        var uncompSize = helper.uncompSize
        var compSize = helper.compSize
        var crc32 = helper.entryInfo.crc

        let fileData: Data
        let byteReader = LittleEndianByteReader(data: data)
        byteReader.offset = helper.dataOffset
        switch helper.entryInfo.compressionMethod {
        case .copy:
            fileData = Data(byteReader.bytes(count: uncompSize.toInt()))
        case .deflate:
            let bitReader = LsbBitReader(byteReader)
            fileData = try Deflate.decompress(bitReader)
            // Sometimes bitReader is misaligned after Deflate decompression, so we need to align before getting end
            // index back.
            bitReader.align()
            byteReader.offset = bitReader.offset
        case .bzip2:
            #if (!SWCOMPRESSION_POD_ZIP) || (SWCOMPRESSION_POD_ZIP && SWCOMPRESSION_POD_BZ2)
                // BZip2 algorithm uses different bit numbering scheme.
                let bitReader = MsbBitReader(byteReader)
                fileData = try BZip2.decompress(bitReader)
                // Sometimes bitReader is misaligned after BZip2 decompression, so we need to align before getting end
                // index back.
                bitReader.align()
                byteReader.offset = bitReader.offset
            #else
                throw ZipError.compressionNotSupported
            #endif
        case .lzma:
            #if (!SWCOMPRESSION_POD_ZIP) || (SWCOMPRESSION_POD_ZIP && SWCOMPRESSION_POD_LZMA)
                byteReader.offset += 4 // Skipping LZMA SDK version and size of properties.
                fileData = try LZMA.decompress(byteReader, LZMAProperties(byteReader), uncompSize.toInt())
            #else
                throw ZipError.compressionNotSupported
            #endif
        default:
            throw ZipError.compressionNotSupported
        }
        let realCompSize = byteReader.offset - helper.dataOffset

        if helper.hasDataDescriptor {
            // Now we need to parse data descriptor itself.
            // First, it might or might not have signature.
            let ddSignature = byteReader.uint32()
            if ddSignature != 0x08074b50 {
                byteReader.offset -= 4
            }
            // Now, let's update with values from data descriptor.
            crc32 = byteReader.uint32()
            if helper.zip64FieldsArePresent {
                compSize = byteReader.uint64()
                uncompSize = byteReader.uint64()
            } else {
                compSize = byteReader.uint64(fromBytes: 4)
                uncompSize = byteReader.uint64(fromBytes: 4)
            }
        }

        guard compSize == realCompSize && uncompSize == fileData.count
            else { throw ZipError.wrongSize }
        let crcError = crc32 != CheckSums.crc32(fileData)

        return (fileData, crcError)
    }

    public static func infoWithHelper(_ data: Data) throws -> [ZipEntryInfoHelper] {
        // Valid ZIP container must contain at least an End of Central Directory record, which is at least 22 bytes long.
        guard data.count >= 22
            else { throw ZipError.notFoundCentralDirectoryEnd }

        let byteReader = LittleEndianByteReader(data: data)
        var entries = [ZipEntryInfoHelper]()

        // First, we are looking for End of Central Directory record, specifically, for its signature.
        byteReader.offset = byteReader.size - 22 // 22 is a minimum amount which could take end of CD record.
        while true {
            // Check signature.
            if byteReader.uint32() == 0x06054b50 {
                // We found it!
                break
            }
            if byteReader.offset == 4 {
                throw ZipError.notFoundCentralDirectoryEnd
            }
            byteReader.offset -= 5
        }

        // Then we are reading End of Central Directory record.
        let endOfCD = try ZipEndOfCentralDirectory(byteReader)
        let cdEntries = endOfCD.cdEntries

        // Now we are ready to read Central Directory itself.
        // But first, we should check for "Archive extra data record" and skip it if present.
        byteReader.offset = endOfCD.cdOffset.toInt()
        if byteReader.uint32() == 0x08064b50 {
            byteReader.offset += byteReader.int(fromBytes: 4)
        } else {
            byteReader.offset -= 4
        }

        for _ in 0..<cdEntries {
            let entry = try ZipEntryInfoHelper(byteReader, endOfCD.currentDiskNumber)
            entries.append(entry)
            // Move to the next Central Directory entry.
            byteReader.offset = entry.nextCdEntryOffset
        }

        return entries
    }

}
