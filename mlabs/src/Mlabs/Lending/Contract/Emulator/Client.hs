-- | Client functions to test contracts in EmulatorTrace monad.
module Mlabs.Lending.Contract.Emulator.Client(
    callUserAct
  , callPriceAct
  , callGovernAct
  , callStartLendex
) where

import Prelude

import Data.Functor (void)

import Mlabs.Data.Ray as R
import Mlabs.Plutus.Contract
import Mlabs.Emulator.Types
import Mlabs.Lending.Logic.Types
import Mlabs.Lending.Contract.Api
import Mlabs.Lending.Contract.Server

import Plutus.Trace.Emulator (EmulatorTrace, throwError, callEndpoint, activateContractWallet, EmulatorRuntimeError(..))
import Plutus.V1.Ledger.Value (unAssetClass)
import qualified Wallet.Emulator as Emulator

---------------------------------------------------------
-- call endpoints (for debug and testing)

-- | Calls user act
callUserAct :: LendexId -> Emulator.Wallet -> UserAct -> EmulatorTrace ()
callUserAct lid wal act = do
  hdl <- activateContractWallet wal (userEndpoints lid)
  void $ case act of
    DepositAct{..}                    -> callEndpoint' hdl $ Deposit act'amount (unAssetClass act'asset)
    BorrowAct{..}                     -> callEndpoint' hdl $ Borrow  act'amount (unAssetClass act'asset) -- (toInterestRateFlag act'rate)
    RepayAct{..}                      -> callEndpoint' hdl $ Repay   act'amount (unAssetClass act'asset) (toInterestRateFlag act'rate)
    SwapBorrowRateModelAct{..}        -> callEndpoint' hdl $ SwapBorrowRateModel (unAssetClass act'asset) (toInterestRateFlag act'rate)
    SetUserReserveAsCollateralAct{..} -> callEndpoint' hdl $ SetUserReserveAsCollateral (unAssetClass act'asset) act'useAsCollateral (R.toInteger act'portion)
    WithdrawAct{..}                   -> callEndpoint' hdl $ Withdraw act'amount (unAssetClass act'asset)
    FlashLoanAct                      -> pure ()
    LiquidationCallAct{..}            ->
      case act'debt of
        BadBorrow (UserId pkh) asset  -> callEndpoint' hdl $ LiquidationCall (unAssetClass act'collateral) pkh (unAssetClass asset) act'debtToCover act'receiveAToken
        _                             -> throwError $ GenericError "Bad borrow has wrong settings"

-- | Calls price oracle act
callPriceAct :: LendexId -> Emulator.Wallet -> PriceAct -> EmulatorTrace ()
callPriceAct lid wal act = do
  hdl <- activateContractWallet wal (oracleEndpoints lid)
  void $ case act of
    SetAssetPriceAct coin rate -> callEndpoint @"set-asset-price" hdl $ SetAssetPrice coin rate

-- | Calls govern act
callGovernAct :: LendexId -> Emulator.Wallet -> GovernAct -> EmulatorTrace ()
callGovernAct lid wal act = do
  hdl <- activateContractWallet wal (adminEndpoints lid)
  void $ case act of
    AddReserveAct cfg  -> callEndpoint @"add-reserve" hdl $ AddReserve cfg

-- | Calls initialisation of state for Lending pool
callStartLendex :: LendexId -> Emulator.Wallet -> StartParams -> EmulatorTrace ()
callStartLendex lid wal sp = do
  hdl <- activateContractWallet wal (adminEndpoints lid)
  void $ callEndpoint @"start-lendex" hdl sp

