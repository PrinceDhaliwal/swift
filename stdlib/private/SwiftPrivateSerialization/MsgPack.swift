//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2015 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
//
// MessagePack encoder and decoder.
//
// MessagePack specification is located at http://msgpack.org/
//
//===----------------------------------------------------------------------===//

/// An encoder for MessagePack.
///
/// This encoder provides a StAX-like interface.
public struct MsgPackEncoder {
  // FIXME: This should be a Sink.
  // Currently it is not for performance reasons (StdlibUnittest
  // code can not be specialized).
  var bytes: [UInt8] = []

  internal var _expectedElementCount: [Int] = [ 0 ]
  internal var _actualElementCount: [Int] = [ 0 ]

  internal mutating func _appendBigEndian(value: Swift.UInt64) {
    var x = value.byteSwapped
    for _ in 0..<8 {
      bytes.append(UInt8(truncatingBitPattern: x))
      x >>= 8
    }
  }

  internal mutating func _appendBigEndian(value: Swift.UInt32) {
    var x = value.byteSwapped
    for _ in 0..<4 {
      bytes.append(UInt8(truncatingBitPattern: x))
      x >>= 8
    }
  }

  internal mutating func _appendBigEndian(value: Swift.UInt16) {
    var x = value.byteSwapped
    for _ in 0..<2 {
      bytes.append(UInt8(truncatingBitPattern: x))
      x >>= 8
    }
  }

  internal mutating func _appendBigEndian(value: Swift.Int64) {
    _appendBigEndian(Swift.UInt64(bitPattern: value))
  }

  internal mutating func _addedElement() {
    _actualElementCount[_actualElementCount.count - 1]++
  }

  public mutating func append(i: Int64) {
    bytes.reserveCapacity(bytes.count + 9)
    bytes.append(0xd3)
    _appendBigEndian(i)

    _addedElement()
  }

  public mutating func append(i: UInt64) {
    bytes.reserveCapacity(bytes.count + 9)
    bytes.append(0xcf)
    _appendBigEndian(i)

    _addedElement()
  }

  public mutating func appendNil() {
    bytes.append(0xc0)

    _addedElement()
  }

  public mutating func append(b: Bool) {
    bytes.append(b ? 0xc3 : 0xc2)

    _addedElement()
  }

  public mutating func append(f: Float32) {
    bytes.reserveCapacity(bytes.count + 5)
    bytes.append(0xca)
    _appendBigEndian(f._toBitPattern())

    _addedElement()
  }

  public mutating func append(f: Float64) {
    bytes.reserveCapacity(bytes.count + 9)
    bytes.append(0xcb)
    _appendBigEndian(f._toBitPattern())

    _addedElement()
  }

  public mutating func append(s: String) {
    let utf8Bytes = Array(s.utf8)
    switch Int64(utf8Bytes.count) {
    case 0...31:
      // fixstr
      bytes.append(0b1010_0000 | UInt8(utf8Bytes.count))
    case 32...0xff:
      // str8
      bytes.append(0xd9)
      bytes.append(UInt8(utf8Bytes.count))
    case 0x100...0xffff:
      // str16
      bytes.append(0xda)
      _appendBigEndian(UInt16(utf8Bytes.count))
    case 0x1_0000...0xffff_ffff:
      // str32
      bytes.append(0xdb)
      _appendBigEndian(UInt32(utf8Bytes.count))
    default:
      // FIXME: better error handling.  Trapping is at least secure.
      fatalError("string is too long")
    }
    bytes += utf8Bytes

    _addedElement()
  }

  public mutating func append(dataBytes: [UInt8]) {
    switch Int64(dataBytes.count) {
    case 0...0xff:
      // bin8
      bytes.append(0xc4)
      bytes.append(UInt8(dataBytes.count))
    case 0x100...0xffff:
      // bin16
      bytes.append(0xc5)
      _appendBigEndian(UInt16(dataBytes.count))
    case 0x1_0000...0xffff_ffff:
      // bin32
      bytes.append(0xc6)
      _appendBigEndian(UInt32(dataBytes.count))
    default:
      // FIXME: better error handling.  Trapping is at least secure.
      fatalError("binary data is too long")
    }
    bytes += dataBytes

    _addedElement()
  }

  public mutating func beginArray(count: Int) {
    switch Int64(count) {
    case 0...0xf:
      // fixarray
      bytes.append(0b1001_0000 | UInt8(count))
    case 0x10...0xffff:
      // array16
      bytes.append(0xdc)
      _appendBigEndian(UInt16(count))
    case 0x1_0000...0xffff_ffff:
      // array32
      bytes.append(0xdd)
      _appendBigEndian(UInt32(count))
    default:
      // FIXME: better error handling.  Trapping is at least secure.
      fatalError("array is too long")
    }

    _expectedElementCount.append(count)
    _actualElementCount.append(0)
  }

  public mutating func endArray() {
    let expectedCount = _expectedElementCount.removeLast()
    let actualCount = _actualElementCount.removeLast()
    if expectedCount != actualCount {
      fatalError("Actual number of elements in the array does not match the expected number")
    }

    _addedElement()
  }

  public mutating func beginMap(mappingCount: Int) {
    switch Int64(mappingCount) {
    case 0...0xf:
      bytes.append(0b1000_0000 | UInt8(mappingCount))
    case 0x10...0xffff:
      bytes.append(0xde)
      _appendBigEndian(UInt16(mappingCount))
    case 0x1_0000...0xffff_ffff:
      bytes.append(0xdf)
      _appendBigEndian(UInt32(mappingCount))
    default:
      // FIXME: better error handling.  Trapping is at least secure.
      fatalError("map is too long")
    }

    _expectedElementCount.append(mappingCount * 2)
    _actualElementCount.append(0)
  }

  public mutating func endMap() {
    let expectedCount = _expectedElementCount.removeLast()
    let actualCount = _actualElementCount.removeLast()
    if expectedCount != actualCount {
      fatalError("Actual number of elements in the map does not match the expected number")
    }

    _addedElement()
  }

  public mutating func appendExtended(type type: Int8, data: [UInt8]) {
    switch Int64(data.count) {
    case 1:
      // fixext1
      bytes.append(0xd4)
    case 2:
      // fixext2
      bytes.append(0xd5)
    case 4:
      // fixext4
      bytes.append(0xd6)
    case 8:
      // fixext8
      bytes.append(0xd7)
    case 16:
      // fixext16
      bytes.append(0xd8)
    case 0...0xff:
      // ext8
      bytes.append(0xc7)
      bytes.append(UInt8(data.count))
    case 0x100...0xffff:
      // ext16
      bytes.append(0xc8)
      _appendBigEndian(UInt16(data.count))
    case 0x1_0000...0xffff_ffff:
      // ext32
      bytes.append(0xc9)
      _appendBigEndian(UInt32(data.count))
    default:
      fatalError("extended data is too long")
    }
    bytes.append(UInt8(bitPattern: type))
    bytes += data
  }
}

internal func _safeUInt32ToInt(x: UInt32) -> Int? {
#if arch(i386) || arch(arm)
  if x > UInt32(Int.max) {
    return nil
  } else {
    return Int(x)
  }
#elseif arch(x86_64) || arch(arm64)
  return Int(x)
#else
  fatalError("unimplemented")
#endif
}

enum MsgPackError : ErrorType {
  case DecodeFailed
}

/// A decoder for MessagePack.
///
/// This decoder provides a StAX-like interface.
public struct MsgPackDecoder {
  // FIXME: This should be a Generator.
  // Currently it is not for performance reasons (StdlibUnittest
  // code can not be specialized).
  //
  // Or maybe not, since the caller might want to know how many
  // bytes were consumed.
  internal let _bytes: [UInt8]

  internal var _consumedCount: Int = 0

  public var consumedCount: Int {
    return _consumedCount
  }

  public init(_ bytes: [UInt8]) {
    self._bytes = bytes
  }

  @noreturn internal func _fail() throws {
    throw MsgPackError.DecodeFailed
  }

  internal func _failIf(@noescape fn: () throws -> Bool) throws {
    if try fn() { try _fail() }
  }

  internal func _unwrapOrFail<T>(maybeValue: Optional<T>) throws -> T {
    if let value = maybeValue {
      return value
    }
    try _fail()
  }

  internal func _haveNBytes(count: Int) throws {
    try _failIf { _bytes.count < _consumedCount + count }
  }

  internal mutating func _consumeByte() throws -> UInt8 {
    try _haveNBytes(1)
    return _bytes[_consumedCount++]
  }

  internal mutating func _consumeByteIf(byte: UInt8) throws {
    try _failIf { try _consumeByte() != byte }
  }

  internal mutating func _readBigEndianUInt16() throws -> UInt16 {
    var result: UInt16 = 0
    for _ in 0..<2 {
      result <<= 8
      result |= UInt16(try _consumeByte())
    }
    return result
  }

  internal mutating func _readBigEndianUInt32() throws -> UInt32 {
    var result: UInt32 = 0
    for _ in 0..<4 {
      result <<= 8
      result |= UInt32(try _consumeByte())
    }
    return result
  }

  internal mutating func _readBigEndianInt64() throws -> Int64 {
    let result = try _readBigEndianUInt64()
    return Int64(bitPattern: result)
  }

  internal mutating func _readBigEndianUInt64() throws -> UInt64 {
    var result: UInt64 = 0
    for _ in 0..<8 {
      result <<= 8
      result |= UInt64(try _consumeByte())
    }
    return result
  }

  internal mutating func _rewind<T>(
    @noescape code: () throws -> T
  ) -> T? {
    let originalPosition = _consumedCount
    do {
      return try code()
    } catch _ as MsgPackError {
      _consumedCount = originalPosition
      return nil
    } catch let e {
      preconditionFailure("unexpected error: \(e)")
    }
  }

  public mutating func readInt64() -> Int64? {
    return _rewind {
      try _consumeByteIf(0xd3)
      return try _readBigEndianInt64()
    }
  }

  public mutating func readUInt64() -> UInt64? {
    return _rewind {
      try _consumeByteIf(0xcf)
      return try _readBigEndianUInt64()
    }
  }

  public mutating func readNil() -> Bool {
    let value: Bool? = _rewind {
      try _consumeByteIf(0xc0)
      return true
    }
    // .Some(true) means nil, nil means fail...
    return value != nil
  }

  public mutating func readBool() -> Bool? {
    return _rewind {
      switch try _consumeByte() {
      case 0xc2:
        return false
      case 0xc3:
        return true
      default:
        try _fail()
      }
    }
  }

  public mutating func readFloat32() -> Float32? {
    return _rewind {
      try _consumeByteIf(0xca)
      let bitPattern = try _readBigEndianUInt32()
      return Float32._fromBitPattern(bitPattern)
    }
  }

  public mutating func readFloat64() -> Float64? {
    return _rewind {
      try _consumeByteIf(0xcb)
      let bitPattern = try _readBigEndianUInt64()
      return Float64._fromBitPattern(bitPattern)
    }
  }

  internal mutating func _consumeBytes(length: Int) throws -> [UInt8] {
    try _haveNBytes(length)
    let result = _bytes[_consumedCount..<_consumedCount + length]
    _consumedCount += length
    return [UInt8](result)
  }

  public mutating func readString() -> String? {
    return _rewind {
      let length: Int
      switch try _consumeByte() {
      case let byte where byte & 0b1110_0000 == 0b1010_0000:
        // fixstr
        length = Int(byte & 0b0001_1111)
      case 0xd9:
        // str8
        let count = try _consumeByte()
        // Reject overlong encodings.
        try _failIf { count <= 0x1f }
        length = Int(count)
      case 0xda:
        // str16
        let count = try _readBigEndianUInt16()
        // Reject overlong encodings.
        try _failIf { count <= 0xff }
        length = Int(count)
      case 0xdb:
        // str32
        let count = try _readBigEndianUInt32()
        // Reject overlong encodings.
        try _failIf { count <= 0xffff }
        length = Int(count)
      default:
        try _fail()
      }
      let utf8 = try _consumeBytes(length)
      return String._fromCodeUnitSequenceWithRepair(UTF8.self, input: utf8).0
    }
  }

  public mutating func readBinary() -> [UInt8]? {
    return _rewind {
      let length: Int
      switch try _consumeByte() {
      case 0xc4:
        // bin8
        length = Int(try _consumeByte())
      case 0xc5:
        // bin16
        let count = try _readBigEndianUInt16()
        // Reject overlong encodings.
        try _failIf { count <= 0xff }
        length = Int(count)
      case 0xc6:
        // bin32
        let count = try _readBigEndianUInt32()
        // Reject overlong encodings.
        try _failIf { count <= 0xffff }
        length = Int(count)
      default:
        try _fail()
      }
      return try _consumeBytes(length)
    }
  }

  public mutating func readBeginArray() -> Int? {
    return _rewind {
      switch try _consumeByte() {
      case let byte where byte & 0b1111_0000 == 0b1001_0000:
        // fixarray
        return Int(byte & 0b0000_1111)
      case 0xdc:
        // array16
        let length = try _readBigEndianUInt16()
        // Reject overlong encodings.
        try _failIf { length <= 0xf }
        return Int(length)
      case 0xdd:
        // array32
        let length = try _readBigEndianUInt32()
        // Reject overlong encodings.
        try _failIf { length <= 0xffff }
        return try _unwrapOrFail(_safeUInt32ToInt(length))
      default:
        try _fail()
      }
    }
  }

  public mutating func readBeginMap() -> Int? {
    return _rewind {
      switch try _consumeByte() {
      case let byte where byte & 0b1111_0000 == 0b1000_0000:
        // fixarray
        return Int(byte & 0b0000_1111)
      case 0xde:
        // array16
        let length = try _readBigEndianUInt16()
        // Reject overlong encodings.
        try _failIf { length <= 0xf }
        return Int(length)
      case 0xdf:
        // array32
        let length = try _readBigEndianUInt32()
        // Reject overlong encodings.
        try _failIf { length <= 0xffff }
        return try _unwrapOrFail(_safeUInt32ToInt(length))
      default:
        try _fail()
      }
    }
  }

  public mutating func readExtended() -> (type: Int8, data: [UInt8])? {
    return _rewind {
      let length: Int
      switch try _consumeByte() {
      case 0xd4:
        // fixext1
        length = 1
      case 0xd5:
        // fixext2
        length = 2
      case 0xd6:
        // fixext4
        length = 4
      case 0xd7:
        // fixext8
        length = 8
      case 0xd8:
        // fixext16
        length = 16
      case 0xc7:
        // ext8
        let count = try _consumeByte()
        // Reject overlong encodings.
        try _failIf {
          count == 1 ||
          count == 2 ||
          count == 4 ||
          count == 8 ||
          count == 16
        }
        length = Int(count)
      case 0xc8:
        // ext16
        let count = try _readBigEndianUInt16()
        try _failIf { count <= 0xff }
        length = Int(count)
      case 0xc9:
        // ext32
        let count = try _readBigEndianUInt32()
        // Reject overlong encodings.
        try _failIf { count <= 0xffff }
        length = Int(count)
      default:
        try _fail()
      }
      let type = try _consumeByte()
      let result = try _consumeBytes(length)
      return (Int8(bitPattern: type), result)
    }
  }
}

public struct MsgPackVariantArray : CollectionType {
  internal var _data: [MsgPackVariant]

  public init(_ data: [MsgPackVariant]) {
    self._data = data
  }

  public var startIndex: Int {
    return _data.startIndex
  }

  public var endIndex: Int {
    return _data.endIndex
  }

  public subscript(i: Int) -> MsgPackVariant {
    return _data[i]
  }

  public var count: Int {
    return _data.count
  }
}

public struct MsgPackVariantMap : CollectionType {
  internal var _data: [(MsgPackVariant, MsgPackVariant)]

  public init() {
    self._data = []
  }

  public init(_ data: [(MsgPackVariant, MsgPackVariant)]) {
    self._data = data
  }

  public init(_ data: [String: MsgPackVariant]) {
    self._data = data.map { (key, value) in
      (MsgPackVariant.String(key), value) }
  }

  public var startIndex: Int {
    return _data.startIndex
  }

  public var endIndex: Int {
    return _data.endIndex
  }

  public subscript(i: Int) -> (MsgPackVariant, MsgPackVariant) {
    return _data[i]
  }

  public var count: Int {
    return _data.count
  }

  internal mutating func _append(
    key newKey: MsgPackVariant, value newValue: MsgPackVariant
  ) {
    let entry = (newKey, newValue)
    _data.append(entry)
  }
}

/// A DOM-like representation of a MessagePack object.
public enum MsgPackVariant {
  case Int64(Swift.Int64)
  case UInt64(Swift.UInt64)
  case Nil
  case Bool(Swift.Bool)
  case Float32(Swift.Float32)
  case Float64(Swift.Float64)
  case String(Swift.String)
  case Binary([UInt8])
  case Array(MsgPackVariantArray)
  case Map(MsgPackVariantMap)
  case Extended(type: Int8, data: [UInt8])

  internal func _serializeToImpl(inout encoder: MsgPackEncoder) {
    switch self {
    case Int64(let i):
      encoder.append(i)

    case UInt64(let i):
      encoder.append(i)

    case Nil:
      encoder.appendNil()

    case Bool(let b):
      encoder.append(b)

    case Float32(let f):
      encoder.append(f)

    case Float64(let f):
      encoder.append(f)

    case String(let s):
      encoder.append(s)

    case Binary(let dataBytes):
      encoder.append(dataBytes)

    case Array(let a):
      encoder.beginArray(a.count)

      // Reserve space assuming homogenous arrays.
      if a.count != 0 {
        switch a[0] {
        case .Float32:
          encoder.bytes.reserveCapacity(
            encoder.bytes.count + a.count * 5)

        case .Int64, .UInt64, .Float64:
          encoder.bytes.reserveCapacity(
            encoder.bytes.count + a.count * 9)

        default:
          ()
        }
      }
      for element in a {
        element._serializeToImpl(&encoder)
      }
      encoder.endArray()

    case Map(let m):
      encoder.beginMap(m.count)
      for (key, value) in m {
        key._serializeToImpl(&encoder)
        value._serializeToImpl(&encoder)
      }
      encoder.endMap()

    case Extended(let type, let data):
      encoder.appendExtended(type: type, data: data)
    }
  }

  public func serializeTo(inout bytes: [UInt8]) {
    bytes += serialize()
  }

  public func serialize() -> [UInt8] {
    var encoder = MsgPackEncoder()
    _serializeToImpl(&encoder)
    return encoder.bytes
  }

  internal static func _deserializeFrom(
    inout decoder: MsgPackDecoder) -> MsgPackVariant? {
    if let i = decoder.readInt64() {
      return MsgPackVariant.Int64(i)
    }
    if let i = decoder.readUInt64() {
      return MsgPackVariant.UInt64(i)
    }
    if decoder.readNil() {
      return MsgPackVariant.Nil
    }
    if let b = decoder.readBool() {
      return MsgPackVariant.Bool(b)
    }
    if let f = decoder.readFloat32() {
      return MsgPackVariant.Float32(f)
    }
    if let f = decoder.readFloat64() {
      return MsgPackVariant.Float64(f)
    }
    if let s = decoder.readString() {
      return MsgPackVariant.String(s)
    }
    if let dataBytes = decoder.readBinary() {
      return MsgPackVariant.Binary(dataBytes)
    }
    if let count = decoder.readBeginArray() {
      var array: [MsgPackVariant] = []
      array.reserveCapacity(count)
      for _ in 0..<count {
        let maybeValue = MsgPackVariant._deserializeFrom(&decoder)
        if let value = maybeValue {
          array.append(value)
        } else {
          return nil
        }
      }
      return .Array(MsgPackVariantArray(array))

    }
    if let count = decoder.readBeginMap() {
      var map: [(MsgPackVariant, MsgPackVariant)] = []
      map.reserveCapacity(count)
      for _ in 0..<count {
        let maybeKey = MsgPackVariant._deserializeFrom(&decoder)
        let maybeValue = MsgPackVariant._deserializeFrom(&decoder)
        if let key = maybeKey, value = maybeValue {
          map.append(key, value)
        } else {
          return nil
        }
      }
      return .Map(MsgPackVariantMap(map))
    }
    if let (type, data) = decoder.readExtended() {
      return MsgPackVariant.Extended(type: type, data: data)
    }
    return nil
  }

  public init?(bytes: [UInt8]) {
    var decoder = MsgPackDecoder(bytes)
    if let result = MsgPackVariant._deserializeFrom(&decoder) {
      self = result
    } else {
      return nil
    }
  }
}

