------------------------ MODULE NonAtomicCasinoFixed --------------------------
(*****************************************************************************)
(* This version of the Casino specification models the transfer method as a  *)
(* separate atomic operation, breaking the atomicity of the enclosing        *)
(* action. Several calls to transfer may be pending, which are represented   *)
(* using a stack. The specification fixes the problems discovered with the   *)
(* NonAtomicCasino specification.                                            *)
(*****************************************************************************)
EXTENDS Integers, Sequences, TLC

Ether == Nat   \* will be overridden for model checking

Address == {"operator", "player", "casino"}
\* add a state between BET_PLACED and IDLE to avoid reentrant calls to DecideBet
State == { "IDLE", "GAME_AVAILABLE", "BET_PLACED", "DECIDING_BET" }
Heads == 0
Tails == 1

(*****************************************************************************)
(* We represent pending calls of the transfer function in a stack containing *)
(* entries of the form [op: Operation, arg: Ether] where `op' describes the  *)
(* state of the transfer operation (called, succeeded or failed). Since      *)
(* `transfer' is called from function `removeFromPot' and `decideBet', more  *)
(* specifically in case the player wins, we tag these operations with RFP    *)
(* (removeFromPot) and PW (playerWins).                                      *)
(*****************************************************************************)
Operation == {"TransferRFP", "SuccessTransferRFP", "FailureTransferRFP", 
               "TransferPW", "SuccessTransferPW", "FailureTransferPW"}
CallEntry == [op: Operation, arg: Ether]

VARIABLES
    state,         \* state of the casino
    transfers,     \* stack of pending transfer operations
    secret,        \* secret chosen at game creation
    guess,         \* player's guess when placing the bet
    pot,           \* value of the pot
    bet,           \* player's bet value
    wallet,        \* amount of ether for each address
    (************************************************************************)
    (* History variables representing the initial funds of the              *)
    (* operator and the player, used for checking that no money is created  *)
    (* or lost.                                                             *)
    (* We use variables rather than constant parameters so that TLC will    *)
    (* check for all possible values rather than for fixed values.          *)
    (************************************************************************)
    operatorFunds,
    playerFunds

vars == <<state, transfers, secret, guess, pot, bet, wallet, operatorFunds, playerFunds>>

TypeOK ==
    /\ state \in State
    /\ transfers \in Seq(CallEntry)
    /\ secret \in {Heads, Tails}
    /\ guess \in {Heads, Tails}
    \* The pot may temporarily become negative when removeFromPot is invoked,
    \* but not if the transfer method succeeds
    /\ pot \in Int
    /\ (\A i \in 1 .. Len(transfers): transfers[i].op \notin {"TransferRFP", "FailureTransferRFP"})
       => pot \in Ether
    /\ bet \in Ether
    /\ wallet \in [Address -> Ether]
    /\ operatorFunds \in Ether
    /\ playerFunds \in Ether

Init ==
    /\ state = "IDLE"
    /\ transfers = << >>
    /\ secret \in {Heads, Tails}
    /\ guess \in {Heads, Tails}
    /\ pot = 0
    /\ bet = 0
    /\ operatorFunds \in Ether
    /\ playerFunds \in Ether 
    /\ wallet = ("operator" :> operatorFunds) 
             @@ ("player" :> playerFunds) 
             @@ ("casino" :> 0)

AddToPot(amount) ==
    /\ wallet["operator"] >= amount   \* implicit "payable" precondition of the function
    /\ pot' = pot + amount
    /\ wallet' = [wallet EXCEPT !["operator"] = @ - amount,
                                !["casino"] = @ + amount]
    /\ UNCHANGED <<state, transfers, secret, guess, bet, operatorFunds, playerFunds>>

\* part of the RemoveFromPot method before the call to transfer
RemoveFromPot1(amount) ==
    \* precondition `noActivebet' extended to new state "DECIDING_BET"
    /\ state \notin {"BET_PLACED", "DECIDING_BET"}
    \* adjust the amount in the pot before the call to transfer
\*    /\ pot >= amount
    /\ pot' = pot - amount
    /\ transfers' = <<[op |-> "TransferRFP", arg |-> amount]>> \o transfers
    /\ UNCHANGED <<state, secret, guess, bet, wallet, operatorFunds, playerFunds>>

\* transfer method called from RemoveToPot: successful execution
RemoveFromPot2Success == 
    /\ Len(transfers) > 0
    /\ Head(transfers).op = "TransferRFP"
    /\ LET amount == Head(transfers).arg
       IN  \* transfer can succeed only if the casino account holds enough money
           /\ wallet["casino"] >= amount
           /\ wallet' = [wallet EXCEPT !["operator"] = @ + amount,
                                       !["casino"] = @ - amount]
           /\ transfers' = <<[op |-> "SuccessTransferRFP", arg |-> amount]>>
                           \o Tail(transfers)
    /\ UNCHANGED <<state, secret, guess, pot, bet, operatorFunds, playerFunds>>

\* transfer method called from RemoveFromPot: failure of execution
RemoveFromPot2Failure == 
    /\ Len(transfers) > 0
    /\ Head(transfers).op = "TransferRFP"
    /\ LET amount == Head(transfers).arg
       IN  transfers' = <<[op |-> "FailureTransferRFP", arg |-> amount]>>
                        \o Tail(transfers)
    /\ UNCHANGED <<state, secret, guess, pot, bet, wallet, operatorFunds, playerFunds>>

\* part of the RemoveFromPot method after successful transfer
RemoveFromPot3Success == 
    /\ Len(transfers) > 0
    /\ Head(transfers).op = "SuccessTransferRFP"
    /\ transfers' = Tail(transfers)
    /\ UNCHANGED <<state, secret, guess, pot, bet, wallet, operatorFunds, playerFunds>>

\* part of the RemoveFromPot method after failed transfer
RemoveFromPot3Failure == 
    /\ Len(transfers) > 0
    /\ Head(transfers).op = "FailureTransferRFP"
    \* roll back the transaction and restore the pot
    /\ pot' = pot + Head(transfers).arg
    /\ transfers' = Tail(transfers)
    /\ UNCHANGED <<state, secret, guess, bet, wallet, operatorFunds, playerFunds>>

CreateGame(_secret) ==
    /\ state = "IDLE"
    /\ secret' = _secret
    /\ state' = "GAME_AVAILABLE"
    /\ UNCHANGED <<guess, transfers, pot, bet, wallet, operatorFunds, playerFunds>>

PlaceBet(amount, _guess) ==
    /\ state = "GAME_AVAILABLE"
    /\ amount <= wallet["player"]  \* implicit precondition "payable"
    /\ amount <= pot  \* explicit precondition of function `placeBet`
    /\ state' = "BET_PLACED"
    /\ guess' = _guess
    /\ bet' = amount
    /\ wallet' = [wallet EXCEPT !["player"] = @ - amount,
                                !["casino"] = @ + amount]
    /\ UNCHANGED <<secret, transfers, pot, operatorFunds, playerFunds>>

\* part of PlayerWins up to call to transfer method
PlayerWins1 ==
    /\ pot' = pot - bet
    /\ state' = "DECIDING_BET"
    /\ transfers' = <<[op |-> "TransferPW", arg |-> 2*bet]>> \o transfers
    /\ UNCHANGED <<secret, guess, bet, wallet, operatorFunds, playerFunds>>

\* transfer method called from PlayerWins: successful execution
PlayerWins2Success == 
    /\ Len(transfers) > 0
    /\ Head(transfers).op = "TransferPW"
    /\ LET amount == Head(transfers).arg
       IN  \* transfer can succeed only if the casino account holds enough money
           /\ wallet["casino"] >= amount
           /\ wallet' = [wallet EXCEPT !["player"] = @ + amount,
                                       !["casino"] = @ - amount]
           /\ transfers' = <<[op |-> "SuccessTransferPW", arg |-> amount]>> 
                           \o Tail(transfers)
    /\ UNCHANGED <<state, secret, guess, pot, bet, operatorFunds, playerFunds>>

\* transfer method called from PlayerWins: failing execution
PlayerWins2Failure == 
    /\ Len(transfers) > 0
    /\ Head(transfers).op = "TransferPW"
    /\ LET amount == Head(transfers).arg
       IN  transfers' = <<[op |-> "FailureTransferPW", arg |-> amount]>> 
                        \o Tail(transfers)
    /\ UNCHANGED <<state, secret, guess, pot, bet, wallet, operatorFunds, playerFunds>>

\* part of PlayerWins after successful transfer
PlayerWins3Success == 
    /\ Len(transfers) > 0
    /\ Head(transfers).op = "SuccessTransferPW"
    /\ bet' = 0
    /\ state' = "IDLE"
    /\ transfers' = Tail(transfers)
    /\ UNCHANGED <<secret, guess, pot, wallet, operatorFunds, playerFunds>>

\* part of PlayerWins after failed transfer
PlayerWins3Failure == 
    /\ Len(transfers) > 0
    /\ Head(transfers).op = "FailureTransferPW"
    /\ pot' = pot + bet \* restore pot
    /\ state' = "BET_PLACED"  \* restore state of the contract
    /\ transfers' = Tail(transfers)
    /\ UNCHANGED <<secret, guess, bet, wallet, operatorFunds, playerFunds>>

OperatorWins ==
    /\ pot' = pot + bet
    /\ wallet' = wallet
    /\ bet' = 0
    /\ state' = "IDLE"
    /\ UNCHANGED <<transfers, secret, guess, wallet, operatorFunds, playerFunds>>

DecideBet ==
    \* This action corresponds to the invocation of `decideBet`.
    \* If the secret was guessed correctly, we initiate PlayerWins, otherwise OperatorWins
    /\ state = "BET_PLACED"
    /\ \/ guess = secret /\ PlayerWins1
       \/ guess # secret /\ OperatorWins

Next ==
    \/ \E amount \in Ether : AddToPot(amount)
    \/ \E amount \in Ether : RemoveFromPot1(amount)
    \/ RemoveFromPot2Success \/ RemoveFromPot2Failure
    \/ RemoveFromPot3Success \/ RemoveFromPot3Failure
    \/ \E _secret \in {Heads, Tails} : CreateGame(_secret)
    \/ \E amount \in Ether, _guess \in {Heads, Tails} : PlaceBet(amount, _guess)
    \/ DecideBet 
    \/ PlayerWins2Success \/ PlayerWins2Failure
    \/ PlayerWins3Success \/ PlayerWins3Failure

\* Require weak fairness for DecideBet, as well as for the actions modeling transfers.
\* In particular, this ensures that a pending transfer called from RemoveFromPot
\* will not block a transfer from PlayerWins.
\* By assuming strong fairness for PlayerWins2Success, we require that transfers
\* to the winning player will not fail indefinitely. In particular, the player
\* cannot forever refuse to be paid out, thereby blocking the casino.
Fairness == 
    /\ WF_vars(DecideBet) 
    /\ WF_vars(RemoveFromPot2Success) /\ WF_vars(RemoveFromPot2Failure)
    /\ WF_vars(RemoveFromPot3Success) /\ WF_vars(RemoveFromPot3Failure)
    /\ SF_vars(PlayerWins2Success) /\ WF_vars(PlayerWins2Failure)
    /\ WF_vars(PlayerWins3Success) /\ WF_vars(PlayerWins3Failure)

Spec == Init /\ [][Next]_vars /\ Fairness

\* No money is created or lost
Inv == 
    wallet["operator"] + wallet["player"] + wallet["casino"] 
    = operatorFunds + playerFunds

\* Liveness: whenever a bet is placed, it will eventually be resolved.
Liveness == (state = "BET_PLACED") ~> (state = "IDLE")

===============================================================================
