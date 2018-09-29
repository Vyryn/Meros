#BN lib.
import BN

#Import the Wallet lib.
import ../Wallet/Wallet

#UI object.
import objects/UIObj
export UIObj

#JS Bindings.
import Bindings/Bindings

#Events lib.
import ec_events

#WebView.
import webview

#Async standard lib.
import asyncdispatch

#String utils standard lib.
import strutils

#Constructor.
proc newUI*(events: EventEmitter, width: int, height: int): UI {.raises: [Exception].} =
    #Create the UI.
    result = newUI(
        events,
        newWebView(
            "Ember Core",
            "",
            width,
            height
        )
    )

    #Add the Bindings.
    result.createBindings()

    #Load the main page.
    if result.webview.eval(
        "document.body.innerHTML = (\"" & MAIN.splitLines().join("\"+\"") & "\");"
    ) != 0:
        raise newException(Exception, "Couldn't evaluate JS in the WebView.")

#Run function.
proc run*(ui: UI) {.async.} =
    ui.webview.run()

#Destructor.
proc destroy*(ui: UI) {.raises: [].} =
    ui.webview.terminate()
