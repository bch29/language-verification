{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DefaultSignatures     #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE GADTs                 #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE RankNTypes            #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE TypeFamilies          #-}
{-# LANGUAGE TypeOperators         #-}

{-|
Type classes from the prelude generalized to work with symbolic values.

Some of this is a hack that relies on the internals of SBV, but I don't think
it'll break (TM).
-}

-- TODO: Add remaining symbolic classes from SBV

module Language.Verification.SymClasses
  (
    SymValue(layerSymbolic)
  , SymBool(..)
  , SymEq(..)
  , SymOrd(..)
  , SymNum(..)
  ) where

import           Data.Typeable
import           Control.Applicative

import qualified Data.SBV           as S
import Data.SBV           hiding (bnot, fromBool, (.==), (.<), (.<=))
import           Data.SBV.Internals (SBV (..))

--------------------------------------------------------------------------------
--  SymValue
--------------------------------------------------------------------------------

errGetSymbolic :: String -> String -> a
errGetSymbolic name' msg = error $
  "Can't get a value out of '" ++ name' ++
  "' with message '" ++ msg ++
  "' Is an instance of a Sym* typeclass missing?"

-- | A type that can be represented by symbolic values.
class (Typeable a) => SymValue a where
  layerSymbolic :: a -> SBV a
  unsafeGetSymbolic :: String -> SBV a -> a

  default layerSymbolic :: (Integral a, SymWord a) => a -> SBV a
  layerSymbolic = fromIntegral

instance SymValue Bool where
  layerSymbolic = S.fromBool
  unsafeGetSymbolic = errGetSymbolic "SBool"

instance SymValue Integer where
  unsafeGetSymbolic = errGetSymbolic "SInteger"

instance SymValue Float where
  layerSymbolic = error "Define this!"
  unsafeGetSymbolic = errGetSymbolic "SFloat"

instance SymValue Double where
  layerSymbolic = error "Define this!"
  unsafeGetSymbolic = errGetSymbolic "SDouble"

instance SymValue AlgReal where
  layerSymbolic = error "Define this!"
  unsafeGetSymbolic = errGetSymbolic "SReal"

instance SymValue a => SymValue (SBV a) where
  layerSymbolic = transmuteSBV
  unsafeGetSymbolic _ = transmuteSBV

instance SymValue Word8  where unsafeGetSymbolic = errGetSymbolic "SWord8"
instance SymValue Word16 where unsafeGetSymbolic = errGetSymbolic "SWord16"
instance SymValue Word32 where unsafeGetSymbolic = errGetSymbolic "SWord32"
instance SymValue Word64 where unsafeGetSymbolic = errGetSymbolic "SWord64"
instance SymValue Int8   where unsafeGetSymbolic = errGetSymbolic "SInt8"
instance SymValue Int16  where unsafeGetSymbolic = errGetSymbolic "SInt16"
instance SymValue Int32  where unsafeGetSymbolic = errGetSymbolic "SInt32"
instance SymValue Int64  where unsafeGetSymbolic = errGetSymbolic "SInt64"

unsafeUnderSymbolic :: (SymValue a, SymValue b, SymValue c) => String -> (a -> b -> c) -> SBV a -> SBV b -> SBV c
unsafeUnderSymbolic msg f x y = layerSymbolic (unsafeGetSymbolic msg x `f` unsafeGetSymbolic msg y)

transmuteSBV :: SBV a -> SBV b
transmuteSBV = SBV . unSBV

--------------------------------------------------------------------------------
--  SymBool
--------------------------------------------------------------------------------

-- | Generalized booleans.
--
-- This is UNSAFE! Never create any new instances!
class SymValue b => SymBool b where
  fromBool :: Bool -> b

  (.&&) :: b -> b -> b
  bnot :: b -> b

  (.||) :: b -> b -> b
  a .|| b = bnot (bnot a .&& bnot b)

instance SymBool Bool where
  fromBool = id
  (.&&) = (&&)
  bnot = not

instance SymBool b => SymBool (SBV b) where
  fromBool = layerSymbolic . fromBool

  x .&& y = transmuteSBV (transmuteSBV x S.&&& transmuteSBV y :: SBV Bool)
  bnot x = transmuteSBV (S.bnot (transmuteSBV x) :: SBV Bool)

--------------------------------------------------------------------------------
--  SymEq
--------------------------------------------------------------------------------

-- | Generalized equality which can return results in the land of generalized
-- booleans.
class (SymValue a, SymBool b) => SymEq b a where
  (.==) :: a -> a -> b

  (./=) :: a -> a -> b
  x ./= y = bnot (x .== y)

instance (Eq a, SymValue a) => SymEq Bool a where
  (.==) = (==)
  (./=) = (/=)

instance (SymValue a, SymBool b) => SymEq (SBV b) (SBV a) where
  x .== y = transmuteSBV (x S..== y)

--------------------------------------------------------------------------------
--  SymOrd
--------------------------------------------------------------------------------

-- | Generalized ordering which can return results in the land of generalized
-- booleans.
class (SymEq b a, SymBool b) => SymOrd b a where
  (.<) :: a -> a -> b

  (.<=) :: a -> a -> b
  x .<= y = (x .< y) .|| (x .== y)

  (.>) :: a -> a -> b
  x .> y = bnot (x .< y)

  (.>=) :: a -> a -> b
  x .>= y = bnot (x .<= y)

instance (Ord a, SymValue a) => SymOrd Bool a where
  (.<) = (<)

instance (SymOrd b a) => SymOrd (SBV b) (SBV a) where
  -- See [Note: Typeable]
  (.<)
    | Just Refl <- eqT :: Maybe (b :~: Bool)
    , Just (BinFunc f) <- findInstance (BinFunc (S..<)) sbvInstances = f
    | otherwise = unsafeUnderSymbolic "SymOrd <" (.<)

--------------------------------------------------------------------------------
--  SymNum
--------------------------------------------------------------------------------

-- | Generalized numbers that don't have to have all the extra cruft that 'Num'
-- forces us to have.
class (SymValue a) => SymNum a where
  (.+) :: a -> a -> a
  (.-) :: a -> a -> a
  (.*) :: a -> a -> a

  default (.+) :: (Num a) => a -> a -> a
  (.+) = (+)

  default (.-) :: (Num a) => a -> a -> a
  (.-) = (-)

  default (.*) :: (Num a) => a -> a -> a
  (.*) = (*)

-- TODO: Add instances for everything that's 'Num' in base.

instance SymNum Integer
instance SymNum Float
instance SymNum Double
instance SymNum S.AlgReal
instance SymNum Word8
instance SymNum Word16
instance SymNum Word32
instance SymNum Word64
instance SymNum Int8
instance SymNum Int16
instance SymNum Int32
instance SymNum Int64

-- See [Note: Typeable]
tryNumTypes
  :: (Typeable a)
  => (forall b. (Num b) => b -> b -> b)
  -> (a -> a -> a)
  -> (a -> a -> a)
tryNumTypes f backup
  | Just (MonoFunc g) <- findInstance (MonoFunc f) sbvInstances = g
  | otherwise = backup

instance (SymNum a) => SymNum (SBV a) where
  (.+) = tryNumTypes (+) (unsafeUnderSymbolic "SymNum +" (.+))
  (.-) = tryNumTypes (-) (unsafeUnderSymbolic "SymNum -" (.-))
  (.*) = tryNumTypes (*) (unsafeUnderSymbolic "SymNum *" (.*))

{- [NOTE: Typeable]

This explanation refers to 'SymNum', but the situation is essentially the same
for 'SymOrd'.

We want instances of 'SymNum' for each of the symbolic types from
SBV that support numeric operations.

The sensible thing to do would be to just do:

instance SymNum (SBV Integer) ...
instance SymNum (SBV Float) ...

and etc. However, we have another constraint that means this isn't good enough.
In order to be able to hoist 'SBV' over the 'NumOp' operator, we need an
instance of 'SymNum (SBV a)' for /every/ 'a' with 'Num a'. Importantly, this
means we need 'Num (SBV (SBV Integer))' and etc, for arbitrarily many layers of
'SBV'.

Obviously it doesn't really make sense to have an 'SBV (SBV Integer)'. That's
why 'unsafeUnderSymbolic' exists: it assumes that 'SBV (SBV a)' means the same
thing as 'SBV a', uses a dirty hack to transmute it to this, then applies the
standard operator and uses a dirty hack to transmute it back.

However, this hack /does not/ work for standard 'SBV Integer' etc, for which we
want to use SBV's actual symbolic functions. Moreover, we can't use overlapping
instances, because the operation to use has to be selected dynamically, thanks
to all the existential types in the various operators.

Therefore, the instance for 'SymNum (SBV a)' falls back to 'Typeable' to provide
a kind of dynamic instance selection. If 'a' matches a particular type that SBV
does in fact define the relevant function for, that function is used. Otherwise,
we fall back to the dirty hacks.

-}

--------------------------------------------------------------------------------
--  Constraint Machinery
--------------------------------------------------------------------------------

class (S.OrdSymbolic a, Num a) => SBVNumeric a
instance (S.OrdSymbolic a, Num a) => SBVNumeric a

-- This is a list of reified instances of 'SBVNumeric'. It's used when
-- dynamically selecting instances to use (see [Note: Typeable]).
-- TODO: Can we use a Map indexed by 'TypeRep's to speed up the lookup?
sbvInstances :: [ExistsDict SBVNumeric]
sbvInstances =
  [ Ex (Proxy :: Proxy SInteger)
  , Ex (Proxy :: Proxy SFloat)
  , Ex (Proxy :: Proxy SDouble)
  , Ex (Proxy :: Proxy SReal)
  , Ex (Proxy :: Proxy SWord8)
  , Ex (Proxy :: Proxy SWord16)
  , Ex (Proxy :: Proxy SWord32)
  , Ex (Proxy :: Proxy SWord64)
  , Ex (Proxy :: Proxy SInt8)
  , Ex (Proxy :: Proxy SInt16)
  , Ex (Proxy :: Proxy SInt32)
  , Ex (Proxy :: Proxy SInt64)
  ]

data ExistsDict p where
  Ex :: (Typeable a, p a) => Proxy a -> ExistsDict p

findInstance :: forall b p f. Typeable b => (forall a. (p a) => f a) -> [ExistsDict p] -> Maybe (f b)
findInstance f = findFirst unpack
  where
    findFirst :: (x -> Maybe y) -> [x] -> Maybe y
    findFirst _ [] = Nothing
    findFirst g (x : xs) = g x <|> findFirst g xs

    unpack :: ExistsDict p -> Maybe (f b)
    unpack (Ex (_ :: Proxy a)) =
      case eqT :: Maybe (a :~: b) of
        Just Refl -> Just f
        Nothing -> Nothing

newtype BinFunc b a = BinFunc (a -> a -> b)
newtype MonoFunc a = MonoFunc (a -> a -> a)
