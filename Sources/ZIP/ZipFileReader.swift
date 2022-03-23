//
//  File.swift
//  
//
//  Created by Eric Ruck on 23/03/2022.
//

import Foundation

public class ZipFileReader {
    private let source: Data
    private let entries: [ZipEntryInfoHelper]
    
    public init(atUrl: URL) throws {
        self.source = try Data.init(contentsOf: atUrl, options: .mappedIfSafe)
        self.entries = try ZipUtil.infoWithHelper(source)
    }
    
    public func data(atPath: String) throws -> Data {
        guard let helper = entries.first(where: { $0.entryInfo.name == atPath }) else {
            throw ZipError.entryNotFound
        }
        return try ZipUtil.getEntryData(source, helper).data
    }

    public func extractAll(toUrl baseUrl: URL) throws {
        for entry in entries {
            if entry.entryInfo.type == .directory || entry.entryInfo.name.hasSuffix("/") {
                // Skip directory, will be created with first file inside
                // TODO Do we want to create the directory here?
                continue
            }
            let filePath = baseUrl.absoluteString + "/" + entry.entryInfo.name
            guard let fileUrl = URL(string: filePath) else {
                throw ZipError.entryNotFound
            }
            try ZipUtil.writeEntryData(source, entry, toUrl: fileUrl)
        }
    }
}
