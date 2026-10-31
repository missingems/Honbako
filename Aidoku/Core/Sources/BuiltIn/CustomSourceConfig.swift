//
//  CustomSourceConfig.swift
//  Aidoku
//
//  Created by Skitty on 5/25/25.
//

import AidokuRunner
import Foundation

enum CustomSourceConfig {
    case demo
    case local
    case komga(KeyNameServer)
    case kavita(KeyNameServer)
    case suwayomi(KeyNameServer)
    #if SUMI
    case honbakoMangaDex
    #endif

    struct KeyNameServer {
        let key: String
        let name: String
        let server: String
    }
}

extension CustomSourceConfig {
    #if SUMI
    /// Only first-party local and user-configured server readers are available in Honbako.
    var isPersonalCollection: Bool {
        switch self {
            case .local, .komga, .kavita, .suwayomi: true
            case .demo, .honbakoMangaDex: false
        }
    }
    #endif

    func toSource() -> AidokuRunner.Source {
        switch self {
            case .demo:
                .demo()
            case .local:
                .local()
            case let .komga(config):
                .komga(key: config.key, name: config.name, server: config.server)
            case let .kavita(config):
                .kavita(key: config.key, name: config.name, server: config.server)
            case let .suwayomi(config):
                .suwayomi(key: config.key, name: config.name, server: config.server)
            #if SUMI
            case .honbakoMangaDex:
                .honbakoMangaDex()
            #endif
        }
    }
}

// MARK: Coding
extension CustomSourceConfig {
    init(from data: Data) throws {
        guard data.count >= 1 else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: [],
                debugDescription: "Invalid byte count"
            ))
        }

        var currentIndex = 1

        func decodeString() throws -> String {
            let length: UInt64 = try decodeVarInt(data, currentIndex: &currentIndex)
            let endIndex = currentIndex.advanced(by: Int(truncatingIfNeeded: length))
            guard endIndex <= data.endIndex && endIndex >= currentIndex else {
                throw DecodingError.dataCorrupted(DecodingError.Context(
                    codingPath: [],
                    debugDescription: "Invalid string length")
                )
            }
            let stringData = data[currentIndex..<endIndex]
            currentIndex = endIndex
            return String(data: stringData, encoding: .utf8) ?? ""
        }

        switch data[0] {
            case 0:
                self = .demo
            case 1:
                let key = try decodeString()
                let name = try decodeString()
                let server = try decodeString()
                self = .komga(.init(key: key, name: name, server: server))
            case 2:
                self = .local
            case 3:
                let key = try decodeString()
                let name = try decodeString()
                let server = try decodeString()
                self = .kavita(.init(key: key, name: name, server: server))
            case 4:
                let key = try decodeString()
                let name = try decodeString()
                let server = try decodeString()
                self = .suwayomi(.init(key: key, name: name, server: server))
            #if SUMI
            case 5:
                self = .honbakoMangaDex
            #endif
            default:
                throw DecodingError.dataCorrupted(.init(
                    codingPath: [],
                    debugDescription: "Invalid type"
                ))
        }
    }

    func encode() -> Data {
        var bytes = Data()

        switch self {
            case .demo:
                bytes.append(0)
            case let .komga(config):
                bytes.append(1)
                for string in [config.key, config.name, config.server] {
                    let utf8 = [UInt8](string.utf8)
                    varInt(UInt64(utf8.count), data: &bytes)
                    bytes.append(contentsOf: utf8)
                }
            case .local:
                bytes.append(2)
            case let .kavita(config):
                bytes.append(3)
                for string in [config.key, config.name, config.server] {
                    let utf8 = [UInt8](string.utf8)
                    varInt(UInt64(utf8.count), data: &bytes)
                    bytes.append(contentsOf: utf8)
                }
            case let .suwayomi(config):
                bytes.append(4)
                for string in [config.key, config.name, config.server] {
                    let utf8 = [UInt8](string.utf8)
                    varInt(UInt64(utf8.count), data: &bytes)
                    bytes.append(contentsOf: utf8)
                }
            #if SUMI
            case .honbakoMangaDex:
                bytes.append(5)
            #endif
        }

        return bytes
    }
}
