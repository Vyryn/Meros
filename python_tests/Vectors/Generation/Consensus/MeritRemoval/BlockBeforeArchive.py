#Types.
from typing import IO, Dict, List, Any

#Transactions class.
from python_tests.Classes.Transactions.Transactions import Transactions

#Consensus classes.
from python_tests.Classes.Consensus.Element import SignedElement
from python_tests.Classes.Consensus.Verification import SignedVerification
from python_tests.Classes.Consensus.MeritRemoval import SignedMeritRemoval
from python_tests.Classes.Consensus.Consensus import Consensus

#Merit classes.
from python_tests.Classes.Merit.BlockHeader import BlockHeader
from python_tests.Classes.Merit.BlockBody import BlockBody
from python_tests.Classes.Merit.Block import Block
from python_tests.Classes.Merit.Merit import Merit

#BLS lib.
import blspy

#Time standard function.
from time import time

#JSON standard lib.
import json

#Transactionss.
transactions: Transactions = Transactions()
#Consensus.
consensus: Consensus = Consensus(
    bytes.fromhex("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"),
    bytes.fromhex("CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC"),
)
#Merit.
merit: Merit = Merit(
    b"MEROS_DEVELOPER_NETWORK",
    60,
    int("FAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", 16),
    100
)

#Add a single Block to create Merit and load a MeritRemoval.
snFile: IO[Any] = open("python_tests/Vectors/Consensus/MeritRemoval/SameNonce.json", "r")
vectors: Dict[str, Any] = json.loads(snFile.read())
merit.add(
    transactions,
    consensus,
    Block.fromJSON(vectors["blockchain"][0])
)
removal = SignedMeritRemoval.fromJSON(vectors["removal"])
removal.nonce = 1
consensus.add(removal.e1)
consensus.add(removal)
snFile.close()

#Generate a Block with a verif and a Block with the removal.
for i in range(0, 2):
    block: Block = Block(
        BlockHeader(
            i + 2,
            merit.blockchain.last(),
            int(time()),
            consensus.getAggregate(
                [(pubKey, i)]
            )
        ),
        BlockBody([
            (
                pubKey,
                i,
                consensus.getMerkle(
                    pubKey,
                    i
                )
            )
        ])
    )

    #Mine it.
    block.header.rehash()
    while int.from_bytes(block.header.hash, "big") < merit.blockchain.difficulty:
        block.header.proof += 1
        block.header.rehash()

    #Add it.
    merit.add(transactions, consensus, block)
    print("Generated Same Nonce Block " + str(block.header.nonce) + ".")

result: Dict[str, Any] = {
    "blockchain": merit.blockchain.toJSON(),
    "consensus":  consensus.toJSON()
}
vectors: IO[Any] = open("python_tests/Vectors/Consensus/MeritRemoval/SameNonce.json", "w")
vectors.write(json.dumps(result))
vectors.close()
