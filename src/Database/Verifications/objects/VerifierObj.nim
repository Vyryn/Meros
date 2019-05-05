#Errors lib.
import ../../../lib/Errors

#Util lib.
import ../../../lib/Util

#Hash lib.
import ../../../lib/Hash

#MinerWallet lib.
import ../../../Wallet/MinerWallet

#DB Function Box object.
import ../../../objects/GlobalFunctionBoxObj

#Merkle lib.
import ../../common/Merkle

#Verification object.
import VerificationObj

#Serialize lib.
import ../../../Network/Serialize/Verifications/SerializeVerification

#Finals lib.
import finals

#Verifier object.
finalsd:
    type Verifier* = ref object
        #DB Function Box.
        db: DatabaseFunctionBox

        #Chain owner.
        key* {.final.}: BLSPublicKey
        keyStr* {.final.}: string

        #Verifier height.
        height*: Natural
        #Amount of Verifications which have been archived.
        archived*: int
        #seq of the Verifications.
        verifications*: seq[Verification]
        #Merkle of the Verifications.
        merkle*: Merkle

#Constructor.
proc newVerifierObj*(
    db: DatabaseFunctionBox,
    key: BLSPublicKey
): Verifier {.forceCheck: [].} =
    result = Verifier(
        db: db,

        key: key,
        keyStr: key.toString(),

        archived: -1,
        verifications: @[],
        merkle: newMerkle()
    )
    result.ffinalizeKey()

    #Load our data from the DB.
    try:
        result.archived = parseInt(result.db.get("verifications_" & result.keyStr))
    except ValueError as e:
        doAssert(false, "Couldn't parse the Verifier's archived which was successfully retrieved from the Database: " & e.msg)
    #If we're not in the DB, add ourselves.
    except DBReadError:
        try:
            result.db.put("verifications_" & result.keyStr, $result.archived)
        except DBWriteError as e:
            doAssert(false, "Couldn't save a new Verifier to the Database: " & e.msg)

    #Populate with the info from the DB.
    result.height = result.archived + 1

# [] operator.
proc `[]`*(
    verifier: Verifier,
    nonce: Natural
): Verification {.forceCheck: [
    IndexError
].} =
    #Check that the nonce isn't out of bounds.
    if nonce >= verifier.height:
        raise newException(IndexError, "That Verifier doesn't have a Verification for that nonce.")

    #If it's in the database...
    if nonce <= verifier.archived:
        #Grab it and return it.
        try:
            result = newVerificationObj(
                verifier.db.get("verifications_" & verifier.key.toString() & "_" & nonce.toBinary()).toHash(384)
            )
        except ValueError as e:
            doAssert(false, "Couldn't parse a Verification we were asked for from the Database: " & e.msg)
        except DBReadError as e:
            doAssert(false, "Couldn't load a Verification we were asked for from the Database: " & e.msg)

        try:
            result.verifier = verifier.key
            result.nonce = nonce
        except FinalAttributeError as e:
            doAssert(false, "Set a final attribute twice when loading a Verification: " & e.msg)
        return

    #Else, return it from memory.
    result = verifier.verifications[nonce - (verifier.archived + 1)]

#Add a Verification to a Verifier.
proc add*(
    verifier: var Verifier,
    verif: Verification
) {.forceCheck: [
    GapError,
    DataExists,
    MeritRemoval
].} =
    #Verify we're not missing Verifications.
    if verif.nonce > verifier.height:
        raise newException(GapError, "Missing Verifications before this Verification.")
    #Verify the Verification's Nonce.
    elif verif.nonce < verifier.height:
        #Verify they didn't submit two Verifications for the same nonce.
        try:
            if verif.hash != verifier[verif.nonce].hash:
                raise newException(MeritRemoval, "Verifier submitted two Verifications with the same nonce.")
        except IndexError as e:
            doAssert(false, "Couldn't grab a Verification we're supposed to have: " & e.msg)

        #Already added.
        raise newException(DataExists, "Verification has already been added.")

    #Verify this Verifier isn't verifying conflicting Entries.

    #Increase the height.
    verifier.height = verifier.height + 1
    #Add the Verification to the seq.
    verifier.verifications.add(verif)
    #Add the Verification to the Merkle.
    verifier.merkle.add(verif.hash)

    #Add the Verification to the Database.
    try:
        verifier.db.put("verifications_" & verifier.key.toString() & "_" & verif.nonce.toBinary(), verif.hash.toString())
    except DBWriteError as e:
        doAssert(false, "Couldn't save a Verification to the Database: " & e.msg)

#Add a MemoryVerification to a Verifier.
proc add*(
    verifier: var Verifier,
    verif: MemoryVerification
) {.forceCheck: [
    ValueError,
    GapError,
    BLSError,
    DataExists,
    MeritRemoval
].} =
    #Verify the signature.
    try:
        verif.signature.setAggregationInfo(
            newBLSAggregationInfo(verif.verifier, cast[Verification](verif).serialize(true))
        )
        if not verif.signature.verify():
            raise newException(ValueError, "Failed to verify the Verification's signature.")
    except ValueError as e:
        fcRaise e
    except BLSError as e:
        fcRaise e

    #Add the Verification.
    try:
        verifier.add(cast[Verification](verif))
    except GapError as e:
        fcRaise e
    except DataExists as e:
        fcRaise e
    except MeritRemoval as e:
        fcRaise e

#Slice operators.
proc `[]`*(
    verifier: Verifier,
    slice: Slice[int]
): seq[Verification] {.forceCheck: [
    IndexError
].} =
    #Extract the slice values.
    var
        a: int = slice.a
        b: int = slice.b

    #Support the initial verifier.archived value (-1).
    if a == -1:
        a = 0

    #Make sure it's a valid slice.
    #We would use Natural for this, except `a` can be -1.
    if 0 > a:
        raise newException(IndexError, "Can't get Verification Slice from Verifier; a was negative.")
    if a > b:
        raise newException(IndexError, "Can't get Verification Slice from Verifier; b was less than a.")

    #Create a seq.
    result = newSeq[Verification](b - a + 1)

    #Grab every Verification.
    try:
        for i in a .. b:
            result[i - a] = verifier[i]
    except IndexError as e:
        fcRaise e

proc `{}`*(
    verifier: Verifier,
    slice: Slice[int]
): seq[MemoryVerification] {.forceCheck: [
    IndexError
].} =
    #Extract the slice values.
    var
        a: int = slice.a
        b: int = slice.b

    #Support the initial verifier.archived value (-1).
    if a == -1:
        a = 0

    #Make sure it's a valid slice.
    if 0 > a:
        raise newException(IndexError, "Can't get MemoryVerification Slice from Verifier; a was negative.")
    if a > b:
        raise newException(IndexError, "Can't get MemoryVerification Slice from Verifier; b was less than a.")

    #Grab the Verifications and cast them.
    try:
        result = cast[seq[MemoryVerification]](verifier[a .. b])
    except IndexError as e:
        fcRaise e