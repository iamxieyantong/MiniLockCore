//
//  Header.swift
//  MiniLockCore
//
//  Created by Mohak Shah on 31/03/17.
//
//

import Foundation
import ObjectMapper
import libsodium

extension MiniLock {
    struct CryptoBoxSizes {
        static let Nonce = crypto_box_noncebytes()
        static let PublicKey = crypto_box_publickeybytes()
        static let PrivateKey = crypto_box_secretkeybytes()
        static let MAC = crypto_box_macbytes()
    }

    struct Header: ImmutableMappable {
        
        enum Errors: Error {
            case ParsingError
        }

        let version: Int
        let ephemeralPublicKey: String
        let decryptInfo: [String: String]
        
        init?(sender: MiniLock.KeyPair, recipients: [MiniLock.Id], fileInfo: FileInfo) {
            guard !recipients.isEmpty else {
                return nil
            }
            
            guard let fileInfoString = fileInfo.toJSONStringWithoutEscapes() else {
                return nil
            }

            // create a nonce for each recipient
            var recipientNonces = [[UInt8]]()
            for _ in 0..<recipients.count {
                let nonce = [UInt8](repeating: 0, count: CryptoBoxSizes.Nonce)
                randombytes_buf(UnsafeMutablePointer(mutating: nonce), nonce.count)
                recipientNonces.append(nonce)
            }

            // encrypt fileInfoString for each recipient
            let fileInfoBytes = [UInt8](fileInfoString.utf8)
            var encryptedFileInfo = [String]()
            
            for i in 0..<recipients.count {
                let cipherText = [UInt8](repeating: 0, count: fileInfoBytes.count + CryptoBoxSizes.MAC)
                let ret = crypto_box_easy(UnsafeMutablePointer(mutating: cipherText),
                                fileInfoBytes,
                                UInt64(fileInfoBytes.count),
                                recipientNonces[i],
                                recipients[i].binary,
                                sender.privateKey)
                
                if ret != 0 {
                    return nil
                }
                
                encryptedFileInfo.append(Data(bytes: cipherText).base64EncodedString())
            }
            
            // put these encrypted strings in their individual decryptInfo objects
            // and encrypt those decryptInfo objects with an ephemeral key pair
            let ephemeralPK = [UInt8](repeating: 0, count: CryptoBoxSizes.PublicKey)
            let ephemeralSK = [UInt8](repeating: 0, count: CryptoBoxSizes.PrivateKey)
            
            crypto_box_keypair(UnsafeMutablePointer(mutating: ephemeralPK), UnsafeMutablePointer(mutating: ephemeralSK))
            self.ephemeralPublicKey = Data(bytes: ephemeralPK).base64EncodedString()

            var decryptInfoList = [String: String]()
            
            for i in 0..<recipients.count {
                guard let jsonString = DecryptInfo(senderId: sender.publicId,
                                             recipientId: recipients[i],
                                             fileInfo: encryptedFileInfo[i]).toJSONString(prettyPrint: false) else {
                                                return nil
                }
                
                let jsonBytes = [UInt8](jsonString.utf8)
                let cipherText = [UInt8](repeating: 0, count: jsonBytes.count + CryptoBoxSizes.MAC)
                let ret = crypto_box_easy(UnsafeMutablePointer(mutating: cipherText),
                                jsonBytes,
                                UInt64(jsonBytes.count),
                                recipientNonces[i],
                                recipients[i].binary,
                                ephemeralSK)
                
                if ret != 0 {
                    return nil
                }
                
                decryptInfoList[Data(bytes: recipientNonces[i]).base64EncodedString()] = Data(bytes: cipherText).base64EncodedString()
                
            }
            
            self.decryptInfo = decryptInfoList
            self.version = MiniLock.FileFormat.Version
        }
        
        init(map: Map) throws {
            version = try map.value("version")
            ephemeralPublicKey = try map.value("ephemeral")
            decryptInfo = try map.value("decryptInfo")
        }
        
        func mapping(map: Map) {
            version 			>>> map["version"]
            ephemeralPublicKey 	>>> map["ephemeral"]
            decryptInfo         >>> map["decryptInfo"]
        }
    }
}

extension MiniLock.Header {
    struct DecryptInfo: ImmutableMappable {
        let senderId, recipientId: MiniLock.Id
        let fileInfo: String
        
        init(senderId: MiniLock.Id, recipientId: MiniLock.Id, fileInfo: String) {
            self.senderId = senderId
            self.recipientId = recipientId
            self.fileInfo = fileInfo
        }
        
        init(map: Map) throws {
            let senderIdString: String = try map.value("senderID")
            let recipientIdString: String = try map.value("recipientID")
            
            guard let senderId = MiniLock.Id(fromBase58String: senderIdString),
                let recipientId = MiniLock.Id(fromBase58String: recipientIdString) else {
                    throw Errors.ParsingError
            }
            
            self.senderId = senderId
            self.recipientId = recipientId
            self.fileInfo = try map.value("fileInfo")
        }
        
        func mapping(map: Map) {
            senderId.base58String       >>> map["senderID"]
            recipientId.base58String    >>> map["recipientID"]
            fileInfo                    >>> map["fileInfo"]
        }
    }
}

extension MiniLock.Header {
    struct FileInfo: ImmutableMappable {
        let key, nonce, hash: String
        
        init(key: [UInt8], nonce: [UInt8], hash: [UInt8]) {
            self.key = Data(bytes: key).base64EncodedString()
            self.nonce = Data(bytes: nonce).base64EncodedString()
            self.hash = Data(bytes: hash).base64EncodedString()
        }
        
        init(map: Map) throws {
            key = try map.value("fileKey")
            nonce = try map.value("fileNonce")
            hash = try map.value("fileHash")
        }
        
        func mapping(map: Map) {
            key     >>> map["fileKey"]
            nonce   >>> map["fileNonce"]
            hash    >>> map["fileHash"]
        }
    }
}

extension BaseMappable {
    func toJSONStringWithoutEscapes() -> String? {
        guard let jsonString = self.toJSONString(prettyPrint: false) else {
            return nil
        }
        
        return jsonString.replacingOccurrences(of: "\\/", with: "/")
    }
}
