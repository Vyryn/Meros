#Util lib.
import lib/Util

#Numerical libs.
import BN
import lib/Base

#Wallet lib.
import Wallet/Wallet

#Lattice lib.
import Database/Lattice/Lattice

#Serialization libs.
import Network/Serialize/SerializeSend
import Network/Serialize/SerializeReceive

#Networking/OS standard libs.
import asyncnet, asyncdispatch

#String utils standard lib.
import strutils

var
    answer: string                         #Answer to questions.

    address: string                        #Address to send/receive from.
    inputNonce: BN                         #Nonce of the Send to Receive from.
    amount: BN                             #Amount we're sending.
    nonce: BN                              #Nonce of the Node.

    wallet: Wallet                         #Wallet.

    send: Send                             #Send object.
    recv: Receive                          #Receive object.

    sendHeader: string =                   #Send header.
        $(char(0)) &
        $(char(0)) &
        $(char(0)) &
        $(char(0))
    recvHeader: string =                   #Receive header.
        $(char(0)) &
        $(char(0)) &
        $(char(1)) &
        $(char(0))
    serialized: string                     #Serialized string.

    client: AsyncSocket = newAsyncSocket() #Socket.

#Get the PrivateKey.
echo "What's the Wallet's Private Key? If you don't have a Wallet, press enter to make one. "
answer = stdin.readLine()

#If they don't have a wallet, create a new one.
if answer == "":
    echo "Creating a new wallet..."
    wallet = newWallet()
    echo "Your Address is:     " & wallet.getAddress() & "."
    echo "Your Private Key is: " & $wallet.getPrivateKey() & "."
    quit(0)

#Create a Wallet from their Private Key.
wallet = newWallet(answer)

#Get the TX type.
echo "Would you like to Send or Receive a TX?"
answer = stdin.readLine()

#Handle a Send.
if answer.toLower() == "send":
    #Get the output/amount/nonce.
    echo "Who would you like to send to?"
    address = stdin.readLine()
    echo "How much would you like to send?"
    amount = newBN(stdin.readLine())
    echo "What nonce is this on your account?"
    nonce = newBN(stdin.readLine())

    #Create the Send.
    send = newSend(
        address,
        amount,
        nonce
    )
    #Mine the Send.
    send.mine("".pad(64, "88").toBN(16))
    #Sign the Send.
    echo "Signing the Send retuned... " & $wallet.sign(send)

    #Create the serialized string.
    serialized = sendHeader & send.serialize() & "\r\n"

#Handle a Receive.
elif answer.toLower() == "receive":
    #Get the intput address/input nonce/amount/nonce.
    echo "Who would you like to receive from?"
    address = stdin.readLine()
    echo "What nonce is the send block on their account?"
    inputNonce = newBN(stdin.readLine())
    echo "What nonce is this on your account?"
    nonce = newBN(stdin.readLine())

    #Create the Receive.
    recv = newReceive(
        address,
        inputNonce,
        nonce
    )
    #Sign the Receive.
    echo "Signing the Receive retuned... " & $wallet.sign(recv)

    #Create the serialized string.
    serialized = recvHeader & recv.serialize() & "\r\n"

else:
    echo "I don't recognize that option."
    quit(-1)

#Connect to the server.
waitFor client.connect("127.0.0.1", Port(5132))
#Send the serialized node.
waitFor client.send(serialized)
