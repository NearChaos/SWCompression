// Copyright (c) 2022 Timofey Solomko
// Licensed under MIT License
//
// See LICENSE for license information

import Foundation
import BitByteData

/// Provides functions for work with ZIP containers.
public class ZipContainer: Container {

    /**
     Contains user-defined extra fields. When either `ZipContainer.info(container:)` or `ZipContainer.open(container:)`
     function encounters extra field without built-in support, it uses this dictionary and tries to find a corresponding
     user-defined extra field. If an approriate custom extra field is found and successfully processed, then the result
     is stored in `ZipEntryInfo.customExtraFields`.

     To enable support of custom extra field one must add a new entry to this dictionary. The value of this entry must
     be a user-defined type which conforms to `ZipExtraField` protocol. The key must be equal to the ID of user-defined
     extra field and type's `id` property.

     - Warning: Modifying this dictionary while either `info(container:)` or `open(container:)` function is being
     executed may cause undefined behavior.
     */
    public static var customExtraFields = [UInt16: ZipExtraField.Type]()

    /**
     Processes ZIP container and returns an array of `ZipEntry` with information and data for all entries.

     - Important: The order of entries is defined by ZIP container and, particularly, by the creator of a given ZIP
     container. It is likely that directories will be encountered earlier than files stored in those directories, but no
     particular order is guaranteed.

     - Parameter container: ZIP container's data.

     - Throws: `ZipError` or any other error associated with compression type, depending on the type of the problem.
     It may indicate that either container is damaged or it might not be ZIP container at all.

     - Returns: Array of `ZipEntry`.
     */
    public static func open(container data: Data) throws -> [ZipEntry] {
        let helpers = try ZipUtil.infoWithHelper(data)
        var entries = [ZipEntry]()

        for helper in helpers {
            if helper.entryInfo.type == .directory {
                entries.append(ZipEntry(helper.entryInfo, nil))
            } else {
                let entryDataResult = try ZipUtil.getEntryData(data, helper)
                entries.append(ZipEntry(helper.entryInfo, entryDataResult.data))
                guard !entryDataResult.crcError
                    else { throw ZipError.wrongCRC(entries) }
            }
        }

        return entries
    }

    /**
     Processes ZIP container and returns an array of `ZipEntryInfo` with information about entries in this container.

     - Important: The order of entries is defined by ZIP container and, particularly, by the creator of a given ZIP
     container. It is likely that directories will be encountered earlier than files stored in those directories, but no
     particular order is guaranteed.

     - Parameter container: ZIP container's data.

     - Throws: `ZipError`, which may indicate that either container is damaged or it might not be ZIP container at all.

     - Returns: Array of `ZipEntryInfo`.
     */
    public static func info(container data: Data) throws -> [ZipEntryInfo] {
        return try ZipUtil.infoWithHelper(data).map { $0.entryInfo }
    }
}
