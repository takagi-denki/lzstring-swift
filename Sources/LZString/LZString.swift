import Foundation

private let keyStrBase64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/="
private let keyStrUriSafe = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+-$"

// FIXME: throw error if invalid unicode
private let getCharFromInt : (Int) -> Character = { a in
    if let scalar = Unicode.Scalar(a) {
        return Character(scalar)
    } else {
        return Character("")
//        return Character(Unicode.Scalar(65533)!)
    } }
private var baseReserveDict = [String:[Character:Int]]()

private typealias GetCharFromInt<T> = (Int) -> T
private typealias GetNextValue = (Int) -> Int

private typealias DecompressData = (value: Int, position: Int, index: Int)
private typealias CompressContext<T> = (dict: [String:Int], dictCreate: [String:Bool], data: T, val: Int, position: Int) where T : RangeReplaceableCollection

private func getBaseValue(alphabet : String, char : Character) -> Int {
    if let charcter =  baseReserveDict[alphabet]?[char] {
        return charcter
    } else {
        baseReserveDict[alphabet] = [Character:Int]()
        for (index, char) in alphabet.enumerated() {
            baseReserveDict[alphabet]![char] = index
        }

        return baseReserveDict[alphabet]![char]!
    }
}

public func compressToBase64(input: String) -> String {
    guard !input.isEmpty else {
        return ""
    }

    let result = _compress(input: input, bitPerChar: 6, charFromInt: { a in String(keyStrBase64[a])})
    switch result.count % 4 {
    case 0:
        return result
    case 1:
        return result + "==="
    case 2:
        return result + "=="
    case 3:
        return result + "="
    default:
        return ""
    }
}

public func decompressFromBase64(input: String) -> String {
    guard !input.isEmpty else {
        return ""
    }

    return _decompress(length: input.count, resetValue: 32, nextValue: { a in getBaseValue(alphabet: keyStrBase64, char: input[a]) })
}

public func compressToUTF16(input: String) -> String {
    guard !input.isEmpty else {
        return ""
    }

    return _compress(input: input, bitPerChar: 15, charFromInt: { a in String(getCharFromInt(a + 32))}) + " "
}

public func decompressFromUTF16(input: String) -> String {
    guard !input.isEmpty else {
        return ""
    }

    return _decompress(length: input.utf16.count, resetValue: 16384, nextValue: { i in Int(input.utf16[i]) - 32 })
}

public func compressToUInt8Array(input: String) -> [UInt8] {
    let compressed : Data = compress(input: input)
    var buffer = [UInt8](repeating: 0, count: compressed.count)

    for i in 0..<(compressed.count / 2) {
        buffer[i * 2] = compressed[i * 2 + 1]
        buffer[i * 2 + 1] = compressed[i * 2]
    }

    return buffer
}

public func decompressFromUInt8Array(input: [UInt8]) -> String {
    guard !input.isEmpty else {
        return ""
    }

    return _decompress(length: input.count / 2, resetValue: 32768, nextValue: {i in
        let lower = Int(input[i * 2]) * 256
        let upper = Int(input[i * 2 + 1])
        return upper + lower
    })
}

public func compressToEncodedURIComponent(input: String) -> String {
    guard !input.isEmpty else {
        return ""
    }

    return _compress(input: input, bitPerChar: 6, charFromInt: { i in String(keyStrUriSafe[i])})
}

public func decompressFromEncodedURIComponent(input: String) -> String {
    guard !input.isEmpty else {
        return ""
    }

    let replaced = input.replacingOccurrences(of: " ", with: "+")

    return _decompress(length: replaced.count, resetValue: 32, nextValue: { a in getBaseValue(alphabet: keyStrUriSafe, char: input[a]) })
}

public func compress(input: String) -> String {
    guard !input.isEmpty else {
        return ""
    }

    return _compress(input: input, bitPerChar: 16, charFromInt: { a in String(getCharFromInt(a)) })
}

public func compress(input: String) -> Data {
    guard !input.isEmpty else {
        return Data()
    }

    return _compress(input: input, bitPerChar: 16, charFromInt: { a in
        return Data([UInt8(a % 256), UInt8(a >> 8)])
    })
}

// TODO: Change Generics
private func _compress<T : RangeReplaceableCollection>(input: String, bitPerChar: Int, charFromInt: GetCharFromInt<T>) -> T {
    guard !input.isEmpty else {
        return T()
    }

    var value = 0
    var wc : [UInt16] = []
    var w : [UInt16] = []
    var enlargeIn = 2
    var dictSize = 3
    var numBits = 2
    var context = (dict: [[UInt16]:Int](), dictCreate: [[UInt16]:Bool](), data: T(), val: 0, position: 0)

    for c in input.utf16 {
        let s = [c]

        if context.dict.index(forKey: s) == nil {
            context.dict[s] = dictSize
            context.dictCreate[s] = true
            dictSize += 1
        }

        wc = w + s

        if context.dict[wc] != nil {
            w = wc
        } else {
            if context.dictCreate.index(forKey: w) != nil {
                if w[0] < 256 {
                    for _ in 0..<numBits {
                        context.val <<= 1

                        if context.position == bitPerChar - 1 {
                            context.position = 0
                            context.data += charFromInt(context.val)
                            context.val = 0
                        } else {
                            context.position += 1
                        }
                    }

                    value = Int(w[0])

                    for _ in 0..<8 {
                        context.val = (context.val << 1) | (value & 1)

                        if context.position == bitPerChar - 1 {
                            context.position = 0
                            context.data += charFromInt(context.val)
                            context.val = 0
                        } else {
                            context.position += 1
                        }

                        value >>= 1
                    }
                } else {
                    value = 1

                    for _ in 0..<numBits {
                        context.val = (context.val << 1) | value

                        if context.position == bitPerChar - 1 {
                            context.position = 0
                            context.data += charFromInt(context.val)
                            context.val = 0
                        } else {
                            context.position += 1
                        }
                        value = 0
                    }

                    value = Int(w[0])

                    for _ in 0..<16 {
                        context.val = (context.val << 1) | (value & 1)

                        if context.position == bitPerChar - 1 {
                            context.position = 0
                            context.data += charFromInt(context.val)
                            context.val = 0
                        } else {
                            context.position += 1
                        }

                        value >>= 1
                    }
                }

                enlargeIn -= 1

                if enlargeIn == 0 {
                    enlargeIn = 2 << (numBits - 1)
                    numBits += 1
                }

                context.dictCreate.removeValue(forKey: w)
            } else {
                value = context.dict[w]!

                for _ in 0..<numBits {
                    context.val = (context.val << 1) | (value & 1)

                    if context.position == bitPerChar - 1 {
                        context.position = 0
                        context.data += charFromInt(context.val)
                        context.val = 0
                    } else {
                        context.position += 1
                    }

                    value >>= 1
                }
            }
            enlargeIn -= 1

            if enlargeIn == 0 {
                enlargeIn = 2 << (numBits - 1)
                numBits += 1
            }
            context.dict[wc] = dictSize
            dictSize += 1
            w = s
        }
    }

    if !w.isEmpty {
        if context.dictCreate.index(forKey: w) != nil {
            if w[0] < 256 {
                for _ in 0..<numBits {
                    context.val <<= 1

                    if context.position == bitPerChar - 1 {
                        context.position = 0
                        context.data += charFromInt(context.val)
                        context.val = 0
                    } else {
                        context.position += 1
                    }
                }

                value = Int(w[0])

                for _ in 0..<8 {
                    context.val = (context.val << 1) | (value & 1)

                    if context.position == bitPerChar - 1 {
                        context.position = 0
                        context.data += charFromInt(context.val)
                        context.val = 0
                    } else {
                        context.position += 1
                    }

                    value >>= 1
                }
            } else {
                value = 1

                for _ in 0..<numBits {
                    context.val = (context.val << 1) | value

                    if context.position == bitPerChar - 1 {
                        context.position = 0
                        context.data += charFromInt(context.val)
                        context.val = 0
                    } else {
                        context.position += 1
                    }

                    value = 0
                }

                value = Int(w[0])

                for _ in 0..<16 {
                    context.val = (context.val << 1) | (value & 1)

                    if context.position == bitPerChar - 1 {
                        context.position = 0
                        context.data += charFromInt(context.val)
                        context.val = 0
                    } else {
                        context.position += 1
                    }

                    value >>= 1
                }
            }

            enlargeIn -= 1

            if enlargeIn == 0 {
                enlargeIn = 2 << (numBits - 1)
                numBits += 1
            }

            context.dictCreate.removeValue(forKey: w)
        } else {
            value = context.dict[w]!

            for _ in 0..<numBits {
                context.val = (context.val << 1) | (value & 1)

                if context.position == bitPerChar - 1 {
                    context.position = 0
                    context.data += charFromInt(context.val)
                    context.val = 0
                } else {
                    context.position += 1
                }

                value >>= 1
            }
        }

        enlargeIn -= 1

        if enlargeIn == 0 {
            enlargeIn = 2 << (numBits - 1)
            numBits += 1
        }
    }
    value = 2

    for _ in 0..<numBits {
        context.val = (context.val << 1) | (value & 1)

        if context.position == bitPerChar - 1 {
            context.position = 0
            context.data += charFromInt(context.val)
            context.val = 0
        } else {
            context.position += 1
        }

        value >>= 1
    }

    while true {
        context.val <<= 1

        if context.position == bitPerChar - 1 {
            context.data += charFromInt(context.val)
            break
        } else {
            context.position += 1
        }
    }

    return context.data
}

public func decompress(input: String) -> String {
    guard !input.isEmpty else {
        return ""
    }

    return _decompress(length: input.utf16.count, resetValue: 32768, nextValue: {i in Int(input.utf16[i])})
}

public func decompress(input: Data) -> String {
    guard !input.isEmpty else {
        return ""
    }

    return _decompress(length: input.count / 2, resetValue: 32768, nextValue: {i in
        let lower = Int(input[i * 2])
        let upper = Int(input[i * 2 + 1])  * 256
        return upper + lower
    })
}

private func _decompress(length: Int, resetValue: Int, nextValue: @escaping GetNextValue) -> String {
    var dict : [Int:[UInt16]] = [0 : [0], 1 : [1], 2 : [2]]
    var next = 0
    var enlargeIn = 4
    var dictSize = 4
    var numBits = 3
    var bits = 0
    var c : UInt16 = 0
    var entry : [UInt16] = []
    var w : [UInt16] = []
    var result = Data()
    var data = (value: nextValue(0), position: resetValue, index: 1)

    func _slide(data: inout DecompressData, maxpower: Int) -> Int {
        var bits = 0
        var power = 1

        while power != maxpower {
            let resb = data.value & data.position
            data.position >>= 1

            if data.position == 0 {
                data.position = resetValue
                data.value = nextValue(data.index)
                data.index += 1
            }

            bits |= (resb > 0 ? 1 : 0) * power
            power <<= 1
        }

        return bits
    }

    bits = _slide(data: &data, maxpower: 2 << 1)
    next = bits

    if next == 0 {
        bits = _slide(data: &data, maxpower: 2 << 7)
        c = UInt16(bits)
    } else if next == 1 {
        bits = _slide(data: &data, maxpower: 2 << 15)
        c = UInt16(bits)
    } else if next == 2 {
        return ""
    }

    w = [c]
    dict[3] = w
    result.append(contentsOf: w.flatMap({ value in
        [UInt8(value >> 8), UInt8(value & 0x00ff)]
    }))

    while true {
        guard data.index <= length else {
            return ""
        }

        bits = _slide(data: &data, maxpower: 2 << (numBits - 1))
        c = UInt16(bits)

        if c == 0 {
            bits = _slide(data: &data, maxpower: 2 << 7)
            dict[dictSize] = [UInt16(bits)]
            dictSize += 1
            c = UInt16(dictSize - 1)
            enlargeIn -= 1
        } else if c == 1 {
            bits = _slide(data: &data, maxpower: 2 << 15)
            dict[dictSize] = [UInt16(bits)]
            dictSize += 1
            c = UInt16(dictSize - 1)
            enlargeIn -= 1
        } else if c == 2 {
            return String(data: result, encoding: String.Encoding.utf16) ?? ""
        }

        if enlargeIn == 0 {
            enlargeIn = 2 << (numBits - 1)
            numBits += 1
        }

        if let e = dict[Int(c)] {
            entry = e
        } else {
            if c == dictSize {
                var tmp = Array(w)
                tmp.append(entry[0])
                entry = tmp
            } else {
                return ""
            }
        }

        result.append(contentsOf: entry.flatMap({ value in
            [UInt8(value >> 8), UInt8(value & 0x00ff)]
        }))
        var tmp = Array(w)
        tmp.append(entry[0])
        dict[dictSize] = tmp
        dictSize += 1
        enlargeIn -= 1
        w = entry

        if enlargeIn == 0 {
            enlargeIn = 2 << (numBits - 1)
            numBits += 1
        }
    }
}

extension String {
    subscript(pos: Int) -> Character {
        return self[String.Index(utf16Offset: pos, in: self)]
    }
}

extension String.UTF16View {
    subscript(pos: Int) -> Unicode.UTF16.CodeUnit {
        return self[String.UTF16View.Index(utf16Offset: pos, in: String(self))]
    }
}
