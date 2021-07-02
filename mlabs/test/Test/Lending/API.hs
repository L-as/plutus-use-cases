module Test.Lending.Api where

import Data.Aeson as A
import Data.Aeson.Encoding as AE
import Data.ByteString (ByteString)
import Data.ByteString.Lazy (fromStrict)
import qualified Plutus.V1.Ledger.Value as Value
import Test.Tasty
import Test.Tasty.HUnit as HU

import Mlabs.Data.Ray as R
import Mlabs.Emulator.Types (Coin(..))
import Mlabs.Lending.Contract.Api  (Deposit(..), Borrow(..), Repay(..), InterestRateFlag(..), LiquidationCall(..), SetUserReserveAsCollateral(..), SwapBorrowRateModel(..), Withdraw(..))

test :: TestTree
test = jsonTests

jsonTests = testGroup "Lending Contract JSON" 
  [ decodeDeposit
  , decodeBorrow
  , decodeRepay
  , decodeWithdraw
  , decodeSetUserReserveAsCollateral
  , decodeLiquidationCall
  ]

decodeDeposit :: TestTree
decodeDeposit = 
  testCase "Decode Deposit" $ do
    let json = "{\"deposit\'amount\":100,\"deposit\'asset\":[{\"unCurrencySymbol\":\"\"},{\"unTokenName\":\"\"}]}"
    let expected = Just $ Deposit 
                    { deposit'amount = 100
                    , deposit'asset  = ("", "") 
                    }
    let actual = decode json :: Maybe Deposit
    HU.assertEqual "Unexpected decode result" expected actual

decodeBorrow :: TestTree
decodeBorrow =
  testCase "Decode Borrow" $ do
    let json = "{\"borrow\'amount\":100,\"borrow\'asset\":[{\"unCurrencySymbol\":\"\"},{\"unTokenName\":\"\"}]}"
    let expected = Just $ Borrow 
                     { borrow'amount = 100
                     , borrow'asset  = ("", "") 
                     }
    let actual = decode json :: Maybe Borrow
    HU.assertEqual "Unexpected decode result" expected actual

decodeRepay :: TestTree
decodeRepay =
  testCase "Decode Repay" $ do
    let json = "{\"repay\'amount\":100,\"repay\'asset\":[{\"unCurrencySymbol\":\"\"},{\"unTokenName\":\"\"}],\"repay\'rate\":0}"
    let expected = Just $ Repay 
                     { repay'amount = 100
                     , repay'asset  = ("", "")
                     , repay'rate   = InterestRateFlag 0
                     }
    let actual = decode json :: Maybe Repay
    HU.assertEqual "Unexpected decode result" expected actual

decodeSwapBorrowRateModel :: TestTree
decodeSwapBorrowRateModel =
  testCase "Decode SwapBorrowRateModel" $ do
    let json = "{\"swapRate\'asset\":[{\"unCurrencySymbol\":\"\"},{\"unTokenName\":\"\"}],\"swapRate\'rate\":0}"
    let expected = Just $ SwapBorrowRateModel 
                     { swapRate'asset = ("", "")
                     , swapRate'rate  = InterestRateFlag 0
                     }
    let actual = decode json :: Maybe SwapBorrowRateModel
    HU.assertEqual "Unexpected decode result" expected actual    

decodeWithdraw :: TestTree
decodeWithdraw =
  testCase "Decode Withdraw" $ do
    let json = "{\"withdraw\'amount\":100,\"withdraw\'asset\":[{\"unCurrencySymbol\":\"\"},{\"unTokenName\":\"\"}]}"
    let expected = Just $ Withdraw 
                     { withdraw'amount = 100
                     , withdraw'asset  = ("", "")
                     }
    let actual = decode json :: Maybe Withdraw
    HU.assertEqual "Unexpected decode result" expected actual

decodeSetUserReserveAsCollateral :: TestTree
decodeSetUserReserveAsCollateral =
  testCase "Decode SetUserReserveAsCollateral" $ do
    let json = "{\"setCollateral'useAsCollateral\":true,\"setCollateral'portion\":333333333333333333333333333,\"setCollateral'asset\":[{\"unCurrencySymbol\":\"\"},{\"unTokenName\":\"\"}]}"
    let expected = Just $ SetUserReserveAsCollateral
                            { setCollateral'asset           = ("", "")
                            , setCollateral'useAsCollateral = True
                            , setCollateral'portion         = 333333333333333333333333333
                            }
    let actual = decode json :: Maybe SetUserReserveAsCollateral
    HU.assertEqual "Unexpected decode result" expected actual

decodeLiquidationCall :: TestTree
decodeLiquidationCall =
  testCase "Decode LiquidationCall" $ do
    let json = "{\"liquidationCall\'collateral\":[{\"unCurrencySymbol\":\"\"},{\"unTokenName\":\"\"}],\"liquidationCall\'debtUser\":{\"getPubKeyHash\":\"abc123\"},\"liquidationCall\'debtAsset\":[{\"unCurrencySymbol\":\"\"},{\"unTokenName\":\"\"}],\"liquidationCall\'debtToCover\":10,\"liquidationCall\'receiveAToken\":true}"
    let expected = Just $ LiquidationCall
                            { liquidationCall'collateral   = ("", "")
                            , liquidationCall'debtUser     = "abc123"
                            , liquidationCall'debtAsset    = ("", "")
                            , liquidationCall'debtToCover  = 10
                            , liquidationCall'receiveAToken = True
                            }
    let actual = decode json :: Maybe LiquidationCall
    HU.assertEqual "Unexpected decode result" expected actual
