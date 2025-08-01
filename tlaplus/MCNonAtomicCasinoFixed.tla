------------------------ MODULE MCNonAtomicCasinoFixed ------------------------
(*****************************************************************************)
(* Instance of NonAtomicCasinoFixed suitable for model checking by bounding  *)
(* the state space. We also bound the number of pending calls to transfer    *)
(* from `removeFromPot` using the bound MaxTransfers.                        *)
(*****************************************************************************)
EXTENDS NonAtomicCasinoFixed

CONSTANT MaxEther, MaxTransfers
ASSUME MaxEther \in Nat /\ MaxTransfers \in Nat

MCEther == 0 .. MaxEther

\* Strengthen the initial condition such that the initial funds of the
\* operator and player are such that all amounts always stay in the
\* restricted set MCEther.
MCInit == \E of, pf \in MCEther :
    /\ of + pf \in MCEther
    /\ operatorFunds = of
    /\ playerFunds = pf
    /\ Init

MCSpec == MCInit /\ [][Next]_vars /\ Fairness

StateConstraint == Len(transfers) <= MaxTransfers
===============================================================================
