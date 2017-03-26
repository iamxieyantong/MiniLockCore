//
//  StreamCryptoBase.swift
//  MiniLockCore
//
//  Created by Mohak Shah on 26/03/17.
//
//

import Foundation
import libsodium
import libb2s

extension MiniLock
{
    /// This is a base class that contains the common entities of Encryptor and Decryptor classes
    /// It doesn't provide any functionalities.
    class StreamCryptoBase {
        struct CryptoBoxSizes {
            static let CipherTextPadding = crypto_secretbox_boxzerobytes()
            static let MessagePadding = crypto_secretbox_zerobytes()
            static let MAC = crypto_secretbox_macbytes()
            static let SecretKey = crypto_secretbox_keybytes()
            static let Nonce = crypto_secretbox_noncebytes()
        }
        
        static let Blake2sOutputLength = 32
        
        enum CryptoError: Error {
            case processComplete
            case inputSizeInvalid
            case decryptionFailed
            case macVerificationFailed
        }
        
        enum ProcessStatus {
            case incomplete, succeeded, failed
        }
        
        var _processStatus: ProcessStatus = .incomplete
        var processStatus: ProcessStatus {
            return _processStatus
        }
        
        var messageBuffer =  [UInt8](repeating: 0, count: CryptoBoxSizes.MessagePadding
            + MiniLock.FileFormat.PlainTextBlockMaxBytes)
        
        var cipherBuffer = [UInt8](repeating: 0, count: CryptoBoxSizes.CipherTextPadding
            + MiniLock.FileFormat.BlockSizeTagLength
            + MiniLock.FileFormat.PlainTextBlockMaxBytes
            + CryptoBoxSizes.MAC)
        
        var fullNonce: [UInt8]
        
        open var fileNonce: [UInt8] {
            return Array(fullNonce[0..<MiniLock.FileFormat.FileNonceBytes])
        }
        
        var blake2SState = blake2s_state()
        var _cipherTextHash = [UInt8](repeating: 0, count: StreamCryptoBase.Blake2sOutputLength)
        open var cipherTextHash: [UInt8] {
            return _cipherTextHash
        }
        
        open let key: [UInt8]
        
        
        init(key: [UInt8], fileNonce: [UInt8]) throws {
            guard key.count == CryptoBoxSizes.SecretKey,
                fileNonce.count == MiniLock.FileFormat.FileNonceBytes else {
                    throw CryptoError.inputSizeInvalid
            }
            
            self.key = key
            fullNonce = fileNonce + [UInt8](repeating: 0, count: CryptoBoxSizes.Nonce - MiniLock.FileFormat.FileNonceBytes)
            
            // init blake2s stream hashing
            _ = withUnsafeMutablePointer(to: &blake2SState) { (statePointer) in
                blake2s_init(statePointer, StreamCryptoBase.Blake2sOutputLength)
            }
        }
        
        func incrementNonce() {
            for i in MiniLock.FileFormat.FileNonceBytes..<CryptoBoxSizes.Nonce {
                fullNonce[i] = fullNonce[i] &+ 1
                
                // byte did not wrap around
                if fullNonce[i] != 0 {
                    break
                }
            }
        }
    }
}

extension Array {
    /// Copies all elements of "array" to self, starting from "index"
    ///
    /// - Parameters:
    ///   - array: Array of elements to copy from
    ///   - index: index of self to start copying from
    mutating func overwrite(with array: [Element], atIndex index: Int) {
        overwrite(with: ArraySlice(array), atIndex: index)
    }
    
    
    /// Copies all elements of "slice" to self, starting from "index"
    ///
    /// - Parameters:
    ///   - slice: ArraySlice of elements to copy from
    ///   - index: index of self to start copying from
    mutating func overwrite(with slice: ArraySlice<Element>, atIndex index: Int) {
        let sliceStart = slice.startIndex
        for i in 0..<slice.count {
            self[index + i] = slice[sliceStart + i]
        }
    }
}
