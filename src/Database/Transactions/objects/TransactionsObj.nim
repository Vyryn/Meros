#Errors lib.
import ../../../lib/Errors

#Hash lib.
import ../../../lib/Hash

#Wallet libs.
import ../../../Wallet/MinerWallet
import ../../../Wallet/Wallet

#Consensus lib.
import ../../Consensus/Consensus

#Merit lib.
import ../../Merit/Merit

#Transactions DB lib.
import ../../Filesystem/DB/TransactionsDB

#Transaction lib.
import ../Transaction as TransactionFile

#Tables standard library.
import tables

type
    Transactions* = object
        #DB Function Box.
        db: DB

        #Mint Nonce.
        mintNonce*: uint32

        #Transactions which have yet to leave Epochs.
        transactions*: Table[string, Transaction]
        #Table of inputs to whoever spent them.
        spent*: Table[string, seq[Hash[384]]]

#Helper functions to convert an input to a string.
func toString*(
    input: Input
): string {.forceCheck: [].} =
    result = input.hash.toString()
    if input of SendInput:
        result &= char(cast[SendInput](input).nonce)

#Get a Data's sender.
proc getSender*(
    transactions: var Transactions,
    data: Data
): EdPublicKey {.forceCheck: [
    DataMissing
].} =
    for b in 0 ..< 16:
        if data.inputs[0].hash.data[b] != 0:
            try:
                return transactions.db.loadDataSender(data.inputs[0].hash)
            except DBReadError:
                raise newException(DataMissing, "Couldn't find the Data's input which was not its sender.")

    try:
        return newEdPublicKey(cast[string](data.inputs[0].hash.data[16 ..< 48]))
    except EdPublicKeyError as e:
        doAssert(false, "Couldn't grab an EdPublicKey from a Data's input: " & e.msg)

#Add a Transaction to the DAG.
proc add*(
    transactions: var Transactions,
    tx: Transaction,
    save: bool = true
) {.forceCheck: [].} =
    if not (tx of Mint):
        #Add the Transaction to the cache.
        transactions.transactions[tx.hash.toString()] = tx

        #Track the spent outputs.
        for input in tx.inputs:
            var inputStr: string = input.toString()
            if not transactions.spent.hasKey(inputStr):
                transactions.spent[inputStr] = transactions.db.loadSpenders(input)

    if save:
        #Save the TX.
        transactions.db.save(tx)

        #If this is a Data, save the sender.
        if tx of Data:
            var data: Data = cast[Data](tx)
            try:
                transactions.db.saveDataSender(data, transactions.getSender(data))
            except DataMissing as e:
                doAssert(false, "Added a Data we don't know the sender of: " & e.msg)

#Get a Transaction by its hash.
proc `[]`*(
    transactions: Transactions,
    hash: Hash[384]
): Transaction {.forceCheck: [
    IndexError
].} =
    #Extract the hash.
    var hashStr: string = hash.toString()

    #Check if the Transaction is in the cache.
    if transactions.transactions.hasKey(hashStr):
        #If it is, return it from the cache.
        try:
            return transactions.transactions[hashStr]
        except KeyError as e:
            doAssert(false, "Couldn't grab a Transaction despite confirming the key exists: " & e.msg)

    #Load the hash from the DB.
    try:
        result = transactions.db.load(hash)
    except DBReadError:
        raise newException(IndexError, "Hash doesn't map to any Transaction.")

#Transactions constructor.
proc newTransactionsObj*(
    db: DB,
    consensus: Consensus,
    merit: Merit
): Transactions {.forceCheck: [].} =
    #Create the object.
    result = Transactions(
        db: db,

        mintNonce: 0,

        transactions: initTable[string, Transaction](),
        spent: initTable[string, seq[Hash[384]]]()
    )

    #Load the mint nonce.
    try:
        result.mintNonce = db.loadMintNonce()
    except DBReadError:
        discard

    #Load the transactions from the DB.
    #Find every Verifier with a Verification still in Epochs.
    var mentioned: Table[string, BLSPublicKey] = initTable[string, BLSPublicKey]()
    try:
        for nonce in max(0, merit.blockchain.height - 5) ..< merit.blockchain.height:
            for record in merit.blockchain[nonce].records:
                mentioned[record.key.toString()] = record.key
    except IndexError as e:
        doAssert(false, "Couldn't load records from the Blockchain while reloading Transactions: " & e.msg)

    #Go through each Verifier.
    var
        #Properties of each Verifier.
        key: BLSPublicKey
        outOfEpochs: int
        height: int
        elements: seq[Element]

        #Hashes of the TXs to reload.
        hashes: Table[string, Hash[384]]
    for keyStr in mentioned.keys():
        try:
            key = mentioned[keyStr]
        except KeyError:
            doAssert(false, "Couldn't get a value by a key produced from .keys().")

        #Find out what slice we're working with.
        try:
            outOfEpochs = db.load(key)
        except DBReadError:
            outOfEpochs = -1
        height = consensus[key].height

        try:
            elements = consensus[key][(outOfEpochs + 1) ..< height]
        except IndexError as e:
            doAssert(false, "Couldn't load elements from a MeritHolder while reloading Transactions: " & e.msg)
        for element in elements:
            if element of Verification:
                hashes[cast[Verification](element).hash.toString()] = cast[Verification](element).hash

    #Load every Transaction.
    for hash in hashes.keys():
        if not result.transactions.hasKey(hash):
            try:
                result.add(db.load(hashes[hash]), false)
            except KeyError:
                doAssert(false, "Couldn't get a value by a key produced from .keys().")
            except DBReadError as e:
                doAssert(false, "Couldn't load a Transaction from the Database: " & e.msg)

#Load a Public Key's UTXOs.
proc getUTXOs*(
    transactions: Transactions,
    key: EdPublicKey
): seq[SendInput] {.forceCheck: [].} =
    try:
        result = transactions.db.loadSpendable(key)
    except DBReadError:
        result = @[]

#Save a Transaction. Do not apply any other checks.
proc save*(
    transactions: var Transactions,
    tx: Transaction
) {.forceCheck: [].} =
    transactions.db.save(tx)

#Save a MeritHolder's out-of-Epoch tip.
proc save*(
    transactions: Transactions,
    key: BLSPublicKey,
    nonce: int
) {.forceCheck: [].} =
    transactions.db.save(key, nonce)

#Mark a Transaction as verified, removing the outputs it spends from spendable.
proc markVerified*(
    transactions: Transactions,
    hash: Hash[384]
) {.forceCheck: [].} =
    var tx: Transaction
    try:
        tx = transactions[hash]
    except IndexError as e:
        doAssert(false, "Tried to mark a non-existent Transaction as verified: " & e.msg)

    if tx of Send:
        transactions.db.spend(cast[Send](tx))

#Delete a hash from the cache.
func del*(
    transactions: var Transactions,
    hash: string
) {.forceCheck: [].} =
    #Grab the transaction.
    var tx: Transaction
    try:
        tx = transactions.transactions[hash]
    except KeyError:
        return

    #Delete the Transaction from the cache.
    transactions.transactions.del(hash)

    #Clear the spent inputs.
    for input in tx.inputs:
        transactions.spent.del(input.toString())

#Load a MeritHolder's out-of-Epoch tip.
proc load*(
    transactions: Transactions,
    key: BLSPublicKey
): int {.forceCheck: [
    DBReadError
].} =
    try:
        result = transactions.db.load(key)
    except DBReadError as e:
        fcRaise e

#Load a Mint UTXO.
proc loadUTXO*(
    transactions: Transactions,
    tx: Hash[384]
): MintOutput {.forceCheck: [
    DBReadError
].} =
    try:
        result = transactions.db.loadMintUTXO(tx)
    except DBReadError as e:
        fcRaise e

#Load a Send UTXO.
proc loadUTXO*(
    transactions: Transactions,
    input: SendInput
): SendOutput {.forceCheck: [
    DBReadError
].} =
    try:
        result = transactions.db.loadSendUTXO(input.hash, input.nonce)
    except DBReadError as e:
        fcRaise e
