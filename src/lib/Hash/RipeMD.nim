#Hash master type.
import HashCommon

#nimcrypto lib.
import nimcrypto

#String utils standard lib.
import strutils

#Define the Hash Type.
type RipeMD_160Hash* = Hash[160]

#RIPEMD 160 hash function.
proc RipeMD_160*(bytesArg: string): RipeMD_160Hash {.raises: [].} =
    #Copy the bytes argument.
    var bytes: string = bytesArg

    #If it's an empty string...
    if bytes.len == 0:
        return RipeMD_160Hash(
            data: ripemd160.digest(EmptyHash, 0).data
        )

    #Digest the byte array.
    result = RipeMD_160Hash(
        data: ripemd160.digest(cast[ptr uint8](addr bytes[0]), uint(bytes.len)).data
    )

#String to RipeMD_160Hash.
func toRipeMD_160Hash*(hash: string): RipeMD_160Hash {.raises: [ValueError].} =
    hash.toHash(160)
