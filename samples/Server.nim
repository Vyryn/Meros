#BN lib.
import BN

#Wallet lib.
import Wallet/Wallet

#Lattice lib.
import Database/Lattice/Lattice

#Serialization libs.
import Network/Serialize/ParseSend
import Network/Serialize/ParseReceive

#Networking standard libs.
import asyncnet, asyncdispatch

var
    server: AsyncSocket = newAsyncSocket() #Server Socket.
    minter: Wallet = newWallet()           #Wallet.
    lattice: Lattice = newLattice()        #Lattice.
    mintIndex: Index = lattice.mint(       #Mint transaction.
        minter.getAddress(),
        newBN("1000000")
    )
    mintRecv: Receive = newReceive(        #Mint Receive.
        mintIndex,
        newBN()
    )

#Sign and add the Mint Receive.
discard minter.sign(mintRecv)
discard lattice.add(mintRecv)

#Print the Private Key and address of the address holding the coins.
echo minter.getAddress() &
    " was minted, and has received, one million coins. Its Private Key is " &
    $minter.getPrivateKey() &
    "."

#Handles a client.
proc handle(client: AsyncSocket) {.async.} =
    echo "Handling a new client..."

    while true:
        #Read the socket data into the line var.
        var line: string = await client.recvLine()
        if line.len == 0:
            return

        var
            #Extract the header.
            header: string = line.substr(0, 4)
            #Parse the header.
            network:    int = int(header[0])
            minVersion: int = int(header[1])
            maxVersion: int = int(header[2])
            msgType:    int = int(header[3])
            msgLength:  int = int(header[4])
        #Remove the header.
        line = line.substr(5, line.len)

        #Handle the different message types.
        case msgType:
            #Send Node.
            of 0:
                var send: Send
                #Try to parse it.
                try:
                    send = line.parseSend()
                except:
                    echo "Invalid Send. " & getCurrentExceptionMsg()
                    continue

                #Print the message info.
                echo "Adding a new Send."
                echo "From:   " & send.getSender()
                echo "To:     " & send.getOutput()
                echo "Amount: " & $send.getAmount()
                echo "\r\n"

                #Print before-balance, if the Lattice accepts it, and the new balance.
                echo "Balance of " & send.getSender() & ":     " & $lattice.getBalance(send.getSender())
                echo "Adding: " &
                    $lattice.add(
                        send
                    )
                echo "New balance of " & send.getSender() & ": " & $lattice.getBalance(send.getSender())

            #Receive Node.
            of 1:
                var recv: Receive
                #Try to parse it.
                try:
                    recv = line.parseReceive()
                except:
                    echo "Invalid Receive. " & getCurrentExceptionMsg()
                    continue

                #Print the message info.
                echo "Adding a new Receive."
                echo "From:   " & recv.getInputAddress()
                echo "To:     " & recv.getSender()
                echo "\r\n"

                #Print before-balance, if the Lattice accepts it, and the new balance.
                echo "Balance of " & recv.getSender() & ":     " & $lattice.getBalance(recv.getSender())
                echo "Adding: " &
                    $lattice.add(
                        recv
                    )
                echo "New balance of " & recv.getSender() & ": " & $lattice.getBalance(recv.getSender()) & "\r\n"

            #Unsupported message.
            else:
                echo "Unsupported message type."

#Start listening.
server.setSockOpt(OptReuseAddr, true)
server.bindAddr(Port(5132))
server.listen()

#Accept new connections infinitely.
while true:
    asyncCheck handle(waitFor server.accept())