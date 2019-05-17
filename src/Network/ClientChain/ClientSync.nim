include ClientHandshake

#Tell the Client we're syncing.
proc startSyncing*(
    client: Client
) {.forceCheck: [
    SocketError,
    ClientError
], async.} =
    #If we're already syncing, do nothing.
    if client.ourState == ClientState.Syncing:
        return

    #Send that we're syncing.
    try:
        await client.send(newMessage(MessageType.Syncing))
    except SocketError as e:
        fcRaise e
    except ClientError as e:
        fcRaise e
    except Exception as e:
        doAssert(false, "Sending a `Syncing` to a Client threw an Exception despite catching all thrown Exceptions: " & e.msg)

    #Bool of if we should still wait for a SyncingAcknowledged.
    #Set to false after 5 seconds.
    var shouldWait: bool = true
    try:
        addTimer(
            5000,
            true,
            func (fd: AsyncFD): bool {.forceCheck: [].} =
                shouldWait = false
        )
    except OSError as e:
        doAssert(false, "Couldn't set a timer due to an OSError: " & e.msg)
    except Exception as e:
        doAssert(false, "Couldn't set a timer due to an Exception: " & e.msg)

    #Discard every message until we get a SyncingAcknowledged.
    while shouldWait:
        var msg: Message
        try:
            msg = await client.recv()
        except SocketError as e:
            fcRaise e
        except ClientError as e:
            fcRaise e
        except Exception as e:
            doAssert(false, "Receiving the response to a `Syncing` from a Client threw an Exception despite catching all thrown Exceptions: " & e.msg)

        if msg.content == SyncingAcknowledged:
            break

    #If we broke because shouldWait expired, raise a client error.
    if not shouldWait:
        raise newException(ClientError, "Client never responded to the fact we were syncing.")

    #Update our state.
    client.ourState = ClientState.Syncing

#Sync an Entry.
proc syncEntry*(
    client: Client,
    hash: Hash[384]
): Future[Entry] {.forceCheck: [
    SocketError,
    ClientError,
    SyncConfigError,
    InvalidMessageError,
    DataMissing
], async.} =
    #If we're not syncing, raise an error.
    if client.ourState != ClientState.Syncing:
        raise newException(SyncConfigError, "This Client isn't configured to sync data.")

    #Send the request.
    try:
        await client.send(newMessage(MessageType.EntryRequest, hash.toString()))
    except SocketError as e:
        fcRaise e
    except ClientError as e:
        fcRaise e
    except Exception as e:
        doAssert(false, "Sending an `EntryRequest` to a Client threw an Exception despite catching all thrown Exceptions: " & e.msg)

    #Get their response.
    var msg: Message
    try:
        msg = await client.recv()
    except SocketError as e:
        fcRaise e
    except ClientError as e:
        fcRaise e
    except Exception as e:
        doAssert(false, "Receiving the response to an `EntryRequest` from a Client threw an Exception despite catching all thrown Exceptions: " & e.msg)

    #Parse the response.
    try:
        case msg.content:
            of MessageType.Claim .. MessageType.Data:
                result = (char(int(msg.content) - int(MessageType.Claim) + 1) & msg.message).parseEntry()

            of MessageType.DataMissing:
                raise newException(DataMissing, "Client didn't have the requested Entry.")

            else:
                raise newException(InvalidMessageError, "Client didn't respond properly to our EntryRequest.")
    except ValueError as e:
        raise newException(InvalidMessageError, "Client didn't respond with a valid Entry to our EntryRequest, as pointed out by a ValueError: " & e.msg)
    except ArgonError as e:
        raise newException(InvalidMessageError, "Client didn't respond with a valid Entry to our EntryRequest, as pointed out by a ArgonError: " & e.msg)
    except BLSError as e:
        raise newException(InvalidMessageError, "Client didn't respond with a valid Entry to our EntryRequest, as pointed out by a BLSError: " & e.msg)
    except EdPublicKeyError as e:
        raise newException(InvalidMessageError, "Client didn't respond with a valid Entry to our EntryRequest, as pointed out by a EdPublicKeyError: " & e.msg)
    except InvalidMessageError as e:
        fcRaise e
    except DataMissing as e:
        fcRaise e

#Sync a Verification.
proc syncVerification*(
    client: Client,
    holder: BLSPublicKey,
    nonce: int
): Future[Verification] {.forceCheck: [
    SocketError,
    ClientError,
    SyncConfigError,
    InvalidMessageError,
    DataMissing
], async.} =
    #If we're not syncin/g, raise an error.
    if client.ourState != ClientState.Syncing:
        raise newException(SyncConfigError, "This Client isn't configured to sync data.")

    #Send the request.
    try:
        await client.send(
            newMessage(
                MessageType.ElementRequest,
                holder.toString() & nonce.toBinary().pad(INT_LEN)
            )
        )
    except SocketError as e:
        fcRaise e
    except ClientError as e:
        fcRaise e
    except Exception as e:
        doAssert(false, "Sending an `ElementRequest` to a Client threw an Exception despite catching all thrown Exceptions: " & e.msg)

    #Get their response.
    var msg: Message
    try:
        msg = await client.recv()
    except SocketError as e:
        fcRaise e
    except ClientError as e:
        fcRaise e
    except Exception as e:
        doAssert(false, "Receiving the response to an `ElementRequest` from a Client threw an Exception despite catching all thrown Exceptions: " & e.msg)

    case msg.content:
        of MessageType.Verification:
            try:
                result = msg.message.parseVerification()
            except ValueError as e:
                raise newException(InvalidMessageError, "Client didn't respond with a valid Verification to our `ElementRequest`, as pointed out by a ValueError: " & e.msg)
            except BLSError as e:
                raise newException(InvalidMessageError, "Client didn't respond with a valid Verification to our `ElementRequest`, as pointed out by a BLSError: " & e.msg)

        of MessageType.DataMissing:
            raise newException(DataMissing, "Client didn't have the requested Verification.")

        else:
            raise newException(InvalidMessageError, "Client didn't respond properly to our `ElementRequest`.")

    if (result.holder != holder) or (result.nonce != nonce):
        raise newException(InvalidMessageError, "Synced a Verification that we didn't request.")

#Sync a Block.
proc syncBlock*(
    client: Client,
    nonce: int
): Future[Block] {.forceCheck: [
    SocketError,
    ClientError,
    SyncConfigError,
    InvalidMessageError,
    DataMissing
], async.} =
    #If we're not syncing, raise an error.
    if client.ourState != ClientState.Syncing:
        raise newException(SyncConfigError, "This Client isn't configured to sync data.")

    #Get the Block hash.
    try:
        await client.send(newMessage(MessageType.GetBlockHash, nonce.toBinary().pad(INT_LEN)))
    except SocketError as e:
        fcRaise e
    except ClientError as e:
        fcRaise e
    except Exception as e:
        doAssert(false, "Sending an `GetBlockHash` to a Client threw an Exception despite catching all thrown Exceptions: " & e.msg)

    #Get their response.
    var msg: Message
    try:
        msg = await client.recv()
    except SocketError as e:
        fcRaise e
    except ClientError as e:
        fcRaise e
    except Exception as e:
        doAssert(false, "Receiving the response to an `GetBlockHash` from a Client threw an Exception despite catching all thrown Exceptions: " & e.msg)

    #Grab the hash.
    case msg.content:
        of MessageType.BlockHash:
            discard

        of MessageType.DataMissing:
            raise newException(DataMissing, "Client didn't have the requested Block.")

        else:
            raise newException(InvalidMessageError, "Client didn't respond properly to our `GetBlockHash`.")

    #Send the request.
    try:
        await client.send(newMessage(MessageType.BlockRequest, msg.message))
    except SocketError as e:
        fcRaise e
    except ClientError as e:
        fcRaise e
    except Exception as e:
        doAssert(false, "Sending an `BlockRequest` to a Client threw an Exception despite catching all thrown Exceptions: " & e.msg)

    #Get their response.
    try:
        msg = await client.recv()
    except SocketError as e:
        fcRaise e
    except ClientError as e:
        fcRaise e
    except Exception as e:
        doAssert(false, "Receiving the response to an `BlockRequest` from a Client threw an Exception despite catching all thrown Exceptions: " & e.msg)

    case msg.content:
        of MessageType.Block:
            try:
                result = msg.message.parseBlock()
            except ValueError as e:
                raise newException(InvalidMessageError, "Client didn't respond with a valid Block to our `BlockRequest`, as pointed out by a ValueError: " & e.msg)
            except ArgonError as e:
                raise newException(InvalidMessageError, "Client didn't respond with a valid Block to our `BlockRequest`, as pointed out by a ArgonError: " & e.msg)
            except BLSError as e:
                raise newException(InvalidMessageError, "Client didn't respond with a valid Block to our `BlockRequest`, as pointed out by a BLSError: " & e.msg)

        of MessageType.DataMissing:
            raise newException(DataMissing, "Client didn't have the requested Block.")

        else:
            raise newException(InvalidMessageError, "Client didn't respond properly to our `BlockRequest`.")

#Tell the Client we're done syncing.
proc stopSyncing*(
    client: Client
) {.forceCheck: [
    SocketError,
    ClientError
], async.} =
    #If we're already not syncing, do nothing.
    if client.ourState != ClientState.Syncing:
        return

    #Send that we're done syncing.
    try:
        await client.send(newMessage(MessageType.SyncingOver))
    except SocketError as e:
        fcRaise e
    except ClientError as e:
        fcRaise e
    except Exception as e:
        doAssert(false, "Sending a `SyncingOver` to a Client threw an Exception despite catching all thrown Exceptions: " & e.msg)

    #Update our state.
    client.ourState = ClientState.Ready