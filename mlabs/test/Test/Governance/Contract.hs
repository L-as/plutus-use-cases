{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeApplications #-}

module Test.Governance.Contract (
  test,
) where

import Data.Functor (void)
import Data.Text (Text)
import PlutusTx.Prelude hiding (error)
import Prelude (error)

-- import Data.Monoid ((<>), mempty)

import Plutus.Contract.Test as PT (
  Wallet,
  assertContractError,
  assertFailedTransaction,
  assertNoFailedTransactions,
  checkPredicateOptions,
  valueAtAddress,
  walletFundsChange,
  (.&&.),
 )

import Mlabs.Plutus.Contract (callEndpoint')
import Plutus.Contract.Test (walletPubKey)
import Plutus.Trace.Emulator (ContractInstanceTag)
import Plutus.Trace.Emulator qualified as Trace
import Plutus.Trace.Emulator.Types (ContractHandle)
import Plutus.V1.Ledger.Scripts (ScriptError (EvaluationError))
import Ledger (PubKeyHash, pubKeyHash)

import Control.Monad.Freer (Eff, Member)
import Data.Semigroup (Last)
import Data.Text as T (isInfixOf)
import Test.Tasty (TestTree, testGroup)

import Mlabs.Governance.Contract.Api (
  Deposit (..),
  GovernanceSchema,
  Withdraw (..),
 )
import Mlabs.Governance.Contract.Server qualified as Gov
import Test.Governance.Init as Test
import Test.Utils (next)

import Ledger.Index (ValidationError (..))

import Plutus.Trace.Effects.RunContract (RunContract)

theContract :: Gov.GovernanceContract ()
theContract = Gov.governanceEndpoints Test.acGOV

type Handle = ContractHandle (Maybe (Last Integer)) GovernanceSchema Text
setup ::
  (Member RunContract effs) =>
  Wallet ->
  (Wallet, Gov.GovernanceContract (), ContractInstanceTag, Eff effs Handle)
setup wallet = (wallet, theContract, Trace.walletInstanceTag wallet, Trace.activateContractWallet wallet theContract)

test :: TestTree
test =
  testGroup
    "Contract"
    [ testGroup
        "Deposit"
        [ testDepositHappyPath
        , testInsuficcientGOVFails
        , testCantDepositWithoutGov
        , testCantDepositNegativeAmount1
        , testCantDepositNegativeAmount2
        ]
    , testGroup
        "Withdraw"
        [ testFullWithdraw
        , testPartialWithdraw
        , testCantWithdrawNegativeAmount
        , testCantWithdrawMoreThandeposited
        , testTradeAndWithdraw
        ]
    ]

-- deposit tests
testDepositHappyPath :: TestTree
testDepositHappyPath =
  let (wallet, _, _, activateWallet) = setup Test.fstWalletWithGOV
      depoAmt1 = 10
      depoAmt2 = 40
      depoAmt = depoAmt1 + depoAmt2
   in checkPredicateOptions
        Test.checkOptions
        "Deposit"
        ( assertNoFailedTransactions
            .&&. walletFundsChange
              wallet
              ( Test.gov (negate depoAmt)
                  <> Test.xgov wallet depoAmt
              )
            .&&. valueAtAddress Test.scriptAddress (== Test.gov depoAmt)
        )
        $ do
          hdl <- activateWallet
          void $ callEndpoint' @Deposit hdl (Deposit depoAmt1)
          next
          void $ callEndpoint' @Deposit hdl (Deposit depoAmt2)
          next

testInsuficcientGOVFails :: TestTree
testInsuficcientGOVFails =
  let (wallet, contract, tag, activateWallet) = setup Test.fstWalletWithGOV
      errCheck = ("InsufficientFunds" `T.isInfixOf`) -- todo probably matching some concrete error type will be better
   in checkPredicateOptions
        Test.checkOptions
        "Cant deposit more GOV than wallet owns"
        ( assertNoFailedTransactions
            .&&. assertContractError contract tag errCheck "Should fail with `InsufficientFunds`"
            .&&. walletFundsChange wallet mempty
        )
        $ do
          hdl <- activateWallet
          void $ callEndpoint' @Deposit hdl (Deposit 1000) -- TODO get value from wallet
          next

testCantDepositWithoutGov :: TestTree
testCantDepositWithoutGov =
  let (wallet, contract, tag, activateWallet) = setup Test.walletNoGOV
      errCheck = ("InsufficientFunds" `T.isInfixOf`)
   in checkPredicateOptions
        Test.checkOptions
        "Cant deposit with no GOV in wallet"
        ( assertNoFailedTransactions
            .&&. assertContractError contract tag errCheck "Should fail with `InsufficientFunds`"
            .&&. walletFundsChange wallet mempty
        )
        $ do
          hdl <- activateWallet
          void $ callEndpoint' @Deposit hdl (Deposit 50)
          next

{- A bit special case at the moment:
   if we try to deposit negative amount without making (positive) deposit beforehand,
   transaction will have to burn xGOV tokens:
   (see in `deposit`: `xGovValue = Validation.xgovSingleton params.nft (coerce ownPkh) amnt`)
   But without prior deposit wallet won't have xGOV tokens to burn,
   so `Contract` will throw `InsufficientFunds` exception
-}
testCantDepositNegativeAmount1 :: TestTree
testCantDepositNegativeAmount1 =
  let (wallet, contract, tag, activateWallet) = setup Test.fstWalletWithGOV
      errCheck = ("InsufficientFunds" `T.isInfixOf`)
   in checkPredicateOptions
        Test.checkOptions
        "Cant deposit negative GOV case 1"
        ( assertNoFailedTransactions
            .&&. assertContractError contract tag errCheck "Should fail with `InsufficientFunds`"
            .&&. walletFundsChange wallet mempty
        )
        $ do
          hdl <- activateWallet
          void $ callEndpoint' @Deposit hdl (Deposit (negate 2))
          next

testCantDepositNegativeAmount2 :: TestTree
testCantDepositNegativeAmount2 =
  let (wallet, _, _, activateWallet) = setup Test.fstWalletWithGOV
      errCheck _ e _ = case e of
        ScriptFailure (EvaluationError _) -> True
        _ -> False
      depoAmt = 20
   in checkPredicateOptions
        Test.checkOptions
        "Cant deposit negative GOV case 2"
        ( assertFailedTransaction errCheck
            .&&. walletFundsChange
              wallet
              ( Test.gov (negate depoAmt)
                  <> Test.xgov wallet depoAmt
              )
            .&&. valueAtAddress Test.scriptAddress (== Test.gov depoAmt)
        )
        $ do
          hdl <- activateWallet
          void $ callEndpoint' @Deposit hdl (Deposit depoAmt)
          next
          void $ callEndpoint' @Deposit hdl (Deposit (negate 2))
          next

-- withdraw tests
testFullWithdraw :: TestTree
testFullWithdraw =
  let (wallet, _, _, activateWallet) = setup Test.fstWalletWithGOV
      depoAmt = 50
   in checkPredicateOptions
        Test.checkOptions
        "Full withdraw"
        ( assertNoFailedTransactions
            .&&. walletFundsChange wallet mempty
        )
        $ do
          hdl <- activateWallet
          next
          void $ callEndpoint' @Deposit hdl (Deposit depoAmt)
          next
          void $ callEndpoint' @Withdraw hdl (Withdraw $ Test.xgovEP wallet depoAmt)
          next

testPartialWithdraw :: TestTree
testPartialWithdraw =
  let (wallet, _, _, activateWallet) = setup Test.fstWalletWithGOV
      depoAmt = 50
      withdrawAmt = 20
      diff = depoAmt - withdrawAmt
   in checkPredicateOptions
        Test.checkOptions
        "Partial withdraw"
        ( assertNoFailedTransactions
            .&&. walletFundsChange wallet (Test.gov (negate diff) <> Test.xgov wallet diff)
            .&&. valueAtAddress Test.scriptAddress (== Test.gov diff)
        )
        $ do
          hdl <- activateWallet
          next
          void $ callEndpoint' @Deposit hdl (Deposit depoAmt)
          next
          void $ callEndpoint' @Withdraw hdl (Withdraw $ Test.xgovEP wallet withdrawAmt)
          next

testCantWithdrawMoreThandeposited :: TestTree
testCantWithdrawMoreThandeposited =
  let (wallet, contract, tag, activateWallet) = setup Test.fstWalletWithGOV
      depoAmt = 20
      withdrawAmt = 50
      errCheck = ("InsufficientFunds" `T.isInfixOf`)
   in checkPredicateOptions
        Test.checkOptions
        "Cant withdraw more than deposited"
        ( assertNoFailedTransactions
            .&&. assertContractError contract tag errCheck "Should fail with `InsufficientFunds`"
            .&&. walletFundsChange wallet (Test.gov (negate depoAmt) <> Test.xgov wallet depoAmt)
            .&&. valueAtAddress Test.scriptAddress (== Test.gov depoAmt)
        )
        $ do
          hdl <- activateWallet
          next
          void $ callEndpoint' @Deposit hdl (Deposit depoAmt)
          next
          void $ callEndpoint' @Withdraw hdl (Withdraw $ Test.xgovEP wallet withdrawAmt)
          next

testCantWithdrawNegativeAmount :: TestTree
testCantWithdrawNegativeAmount =
  let (wallet, _, _, activateWallet) = setup Test.fstWalletWithGOV
      errCheck _ e _ = case e of NegativeValue _ -> True; _ -> False
      depoAmt = 50
   in checkPredicateOptions
        Test.checkOptions
        "Cant withdraw negative xGOV amount"
        ( assertFailedTransaction errCheck
            .&&. walletFundsChange
              wallet
              ( Test.gov (negate depoAmt)
                  <> Test.xgov wallet depoAmt
              )
            .&&. valueAtAddress Test.scriptAddress (== Test.gov depoAmt)
        )
        $ do
          hdl <- activateWallet
          void $ callEndpoint' @Deposit hdl (Deposit depoAmt)
          next
          void $ callEndpoint' @Withdraw hdl (Withdraw $ Test.xgovEP wallet (negate 1))
          next

testTradeAndWithdraw :: TestTree
testTradeAndWithdraw = 
  let (wallet1, _, _, activateWallet1) = setup Test.fstWalletWithGOV
      (wallet2, _, _, activateWallet2) = setup Test.sndWalletWithGOV
  in checkPredicateOptions
     Test.checkOptions
     "Trade"
     ( assertNoFailedTransactions
       .&&. walletFundsChange
              wallet1
              (Test.gov (negate 50) + Test.xgov wallet1 35)
       .&&. walletFundsChange 
              wallet2
              (Test.xgov wallet2 5 + Test.xgov wallet1 5 + Test.gov 5)
     )
     $ do
       h1 <- activateWallet1
       h2 <- activateWallet2
       void $ callEndpoint' @Deposit h1 (Deposit 50)
       void $ callEndpoint' @Deposit h2 (Deposit 40)
       next
       void $ payXGov wallet1 wallet2 15
       next
       void $ callEndpoint' @Withdraw h2 $ Withdraw $
                                            Test.xgovEP wallet2 35
                                            <> Test.xgovEP wallet1 10
       next                 

walletPKH = pubKeyHash . walletPubKey

payXGov wallet1 wallet2 walletOneXGovAmt = 
  Trace.payToWallet wallet1 wallet2 $ Test.xgov wallet1 walletOneXGovAmt
