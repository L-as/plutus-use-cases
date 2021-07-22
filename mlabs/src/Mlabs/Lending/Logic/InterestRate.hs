-- | Calculate interest rate parameters
module Mlabs.Lending.Logic.InterestRate(
    updateReserveInterestRates
  , getLiquidityRate
  , getNormalisedIncome
  , getCumulatedLiquidityIndex
  , addDeposit
  , getCumulativeBalance
)  where

import           PlutusTx.Prelude

import           Mlabs.Data.Ray            (Ray)
import qualified Mlabs.Data.Ray            as R
import qualified Mlabs.Lending.Logic.Types as Types
import           Mlabs.Lending.Logic.Types (Wallet(..), Reserve(..), ReserveInterest(..))

{-# INLINABLE updateReserveInterestRates #-}
-- |
updateReserveInterestRates :: Integer -> Types.Reserve -> Types.Reserve
updateReserveInterestRates currentTime reserve = reserve { reserve'interest = nextInterest reserve }
  where
    nextInterest Types.Reserve{..} = reserve'interest
      { ri'liquidityRate     = liquidityRate
      , ri'liquidityIndex    = getCumulatedLiquidityIndex liquidityRate yearDelta $ reserve'interest.ri'liquidityIndex
      , ri'normalisedIncome  = getNormalisedIncome liquidityRate yearDelta $ reserve'interest.ri'liquidityIndex
      , ri'lastUpdateTime    = currentTime
      }
      where
        yearDelta      = getYearDelta lastUpdateTime currentTime
        liquidityRate  = getLiquidityRate reserve
        lastUpdateTime = reserve'interest.ri'lastUpdateTime

{-# INLINABLE getYearDelta #-}
getYearDelta :: Integer -> Integer -> Ray
getYearDelta t0 t1 = R.fromInteger (max 0 $ t1 - t0) * secondsPerSlot * R.recip secondsPerYear
  where
    secondsPerSlot = R.fromInteger 1
    secondsPerYear = R.fromInteger 31622400

{-# INLINABLE getCumulatedLiquidityIndex #-}
getCumulatedLiquidityIndex :: Ray -> Ray -> Ray -> Ray
getCumulatedLiquidityIndex liquidityRate yearDelta prevLiquidityIndex =
  (liquidityRate * yearDelta + R.fromInteger 1) * prevLiquidityIndex

{-# INLINABLE getNormalisedIncome #-}
getNormalisedIncome :: Ray -> Ray -> Ray -> Ray
getNormalisedIncome liquidityRate yearDelta prevLiquidityIndex =
  (liquidityRate * yearDelta + R.fromInteger 1) * prevLiquidityIndex

{-# INLINABLE getLiquidityRate #-}
getLiquidityRate :: Types.Reserve -> Ray
getLiquidityRate Types.Reserve{..} = r * u
  where
    u = getUtilisation reserve'wallet
    r = getBorrowRate (ri'interestModel reserve'interest) u

{-# INLINABLE getUtilisation #-}
getUtilisation :: Types.Wallet -> Ray
getUtilisation Types.Wallet{..} = wallet'borrow R.% liquidity
  where
    liquidity = wallet'deposit + wallet'borrow

{-# INLINABLE getBorrowRate #-}
getBorrowRate :: Types.InterestModel -> Ray -> Ray
getBorrowRate Types.InterestModel{..} u
  | u <= uOptimal = im'base + im'slope1 * (u * R.recip uOptimal)
  | otherwise     = im'base + im'slope2 * (u - uOptimal) * R.recip (R.fromInteger 1 - uOptimal)
  where
    uOptimal = im'optimalUtilisation

{-# INLINABLE addDeposit #-}
addDeposit :: Ray -> Integer -> Types.Wallet -> Either String Types.Wallet
addDeposit normalisedIncome amount wal
  | newDeposit >= 0 = Right wal
      { wallet'deposit       = max 0 newDeposit
      , wallet'scaledBalance = max (R.fromInteger 0) $ wallet'scaledBalance wal + R.fromInteger amount * R.recip normalisedIncome
      }
  | otherwise       = Left "Negative deposit"
  where
    newDeposit = wallet'deposit wal + amount

{-# INLINABLE getCumulativeBalance #-}
getCumulativeBalance :: Ray -> Types.Wallet -> Ray
getCumulativeBalance normalisedIncome Types.Wallet{..} =
  wallet'scaledBalance * normalisedIncome

