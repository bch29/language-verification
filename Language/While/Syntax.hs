{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE DeriveDataTypeable    #-}
{-# LANGUAGE DeriveFunctor         #-}
{-# LANGUAGE DeriveTraversable     #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE GADTs                 #-}
{-# LANGUAGE LambdaCase            #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE PatternSynonyms       #-}
{-# LANGUAGE RankNTypes            #-}
{-# LANGUAGE TypeSynonymInstances  #-}


module Language.While.Syntax where

import           Data.String                      (IsString (..))

import           Data.SBV
import           Data.Vinyl                       (Rec (RNil))

import           Control.Lens                     hiding ((...), (.>))
import           Control.Monad.State
import           Data.Map                         (Map)
import qualified Data.Map                         as Map

import           Language.Expression
import           Language.Expression.Curry
import           Language.Expression.Ops.General
import           Language.Expression.Ops.Standard (PureEval (..))
import           Language.Expression.Pretty

--------------------------------------------------------------------------------
--  Operator kind
--------------------------------------------------------------------------------

data WhileOpKind as r where
  OpLit             :: Integer -> WhileOpKind '[]                 Integer
  OpAdd, OpSub, OpMul          :: WhileOpKind '[Integer, Integer] Integer
  OpEq, OpLT, OpLE, OpGT, OpGE :: WhileOpKind '[Integer, Integer] Bool
  OpAnd, OpOr                  :: WhileOpKind '[Bool   , Bool]    Bool
  OpNot                        :: WhileOpKind '[Bool]             Bool


instance (Applicative f, Applicative g) =>
  EvalOpMany f (PureEval g) WhileOpKind where

  evalMany = \case
    OpLit x -> \_ -> pure (pure x)

    OpAdd -> pure . runcurryA (+)
    OpSub -> pure . runcurryA (-)
    OpMul -> pure . runcurryA (*)

    OpEq -> pure . runcurryA (==)
    OpLT -> pure . runcurryA (<)
    OpLE -> pure . runcurryA (<=)
    OpGT -> pure . runcurryA (>)
    OpGE -> pure . runcurryA (>=)

    OpAnd -> pure . runcurryA (&&)
    OpOr -> pure . runcurryA (||)

    OpNot -> pure . runcurryA not

instance (Applicative f) => EvalOpMany f SBV WhileOpKind where
  evalMany = \case
    OpLit x -> \_ -> pure (fromIntegral x)

    OpAdd -> pure . runcurry (+)
    OpSub -> pure . runcurry (-)
    OpMul -> pure . runcurry (*)

    OpEq -> pure . runcurry (.==)
    OpLT -> pure . runcurry (.<)
    OpLE -> pure . runcurry (.<=)
    OpGT -> pure . runcurry (.>)
    OpGE -> pure . runcurry (.>=)

    OpAnd -> pure . runcurry (&&&)
    OpOr -> pure . runcurry (|||)

    OpNot -> pure . runcurry bnot

instance EqOpMany WhileOpKind where
  liftEqMany (OpLit x) (OpLit y) _ = \_ _ -> x == y
  liftEqMany OpAdd OpAdd k = k
  liftEqMany OpSub OpSub k = k
  liftEqMany OpMul OpMul k = k
  liftEqMany OpEq  OpEq  k = k
  liftEqMany OpLT  OpLT  k = k
  liftEqMany OpLE  OpLE  k = k
  liftEqMany OpGT  OpGT  k = k
  liftEqMany OpGE  OpGE  k = k
  liftEqMany OpAnd OpAnd k = k
  liftEqMany OpOr  OpOr  k = k
  liftEqMany OpNot OpNot k = k
  liftEqMany _ _ _ = \_ _ -> False

prettys1Binop ::
  (Pretty1 t) =>
  Int -> String -> (Int -> t a -> t b -> ShowS)
prettys1Binop prec opStr = \p x y ->
  showParen (p > prec) $ prettys1Prec (prec + 1) x
                       . showString opStr
                       . prettys1Prec (prec + 1) y

instance PrettyOpMany WhileOpKind where
  prettysPrecMany = flip $ \case
    OpAdd -> runcurry . prettys1Binop 5 " + "
    OpSub -> runcurry . prettys1Binop 5 " - "
    OpMul -> runcurry . prettys1Binop 6 " * "

    OpEq -> runcurry . prettys1Binop 4 " = "

    OpLT -> runcurry . prettys1Binop 4 " < "
    OpLE -> runcurry . prettys1Binop 4 " <= "
    OpGT -> runcurry . prettys1Binop 4 " > "
    OpGE -> runcurry . prettys1Binop 4 " >= "

    OpNot ->
      \p ->
        runcurry $ \x -> showParen (p > 8) $ showString "! " . prettys1Prec 9 x
    OpAnd -> runcurry . prettys1Binop 3 " && "
    OpOr -> runcurry . prettys1Binop 2 " || "

    OpLit x -> \_ _ -> shows x

--------------------------------------------------------------------------------
--  Operators
--------------------------------------------------------------------------------

type WhileOp = GeneralOp WhileOpKind

--------------------------------------------------------------------------------
--  Variables
--------------------------------------------------------------------------------

data WhileVar l a where
  WhileVar :: l -> WhileVar l Integer

instance Pretty l => Pretty1 (WhileVar l) where
  pretty1 (WhileVar l) = pretty l

--------------------------------------------------------------------------------
--  Expressions
--------------------------------------------------------------------------------

type WhileExpr l = Expr WhileOp (WhileVar l)

instance Num (WhileExpr l Integer) where
  fromInteger x = EOp (Op (OpLit x) RNil)

  (+) = EOp ... rcurry (Op OpAdd)
  (*) = EOp ... rcurry (Op OpMul)
  (-) = EOp ... rcurry (Op OpSub)
  abs = error "can't take abs of expressions"
  signum = error "can't take signum of expressions"

instance IsString s => IsString (WhileExpr s Integer) where
  fromString = EVar . WhileVar . fromString

--------------------------------------------------------------------------------
--  Commands
--------------------------------------------------------------------------------

data Command l a
  = CAnn a (Command l a)
  | CSeq (Command l a) (Command l a)
  | CSkip
  | CAssign l (WhileExpr l Integer)
  | CIf (WhileExpr l Bool) (Command l a) (Command l a)
  | CWhile (WhileExpr l Bool) (Command l a)

instance (Pretty l, Pretty a) => Pretty (Command l a) where
  prettysPrec p = \case
    CAnn ann c ->
      showParen (p > 10) $ showString "{ "
                         . prettys ann
                         . showString " }\n"
                         . prettys c
    CSeq c1 c2 ->
      showParen (p > 10) $ prettys c1 . showString ";\n" . prettys c2
    CSkip -> showString "()"
    CAssign v e ->
      showParen (p > 10) $ prettys v . showString " := " . prettys e
    CIf cond c1 c2 ->
      showParen (p > 10) $ showString "if "
                         . prettysPrec 11 cond
                         . showString " then\n"
                         . prettysPrec 11 c1
                         . showString "\nelse\n"
                         . prettysPrec 11 c2
    CWhile cond body ->
      showParen (p > 10) $ showString "while "
                         . prettysPrec 11 cond
                         . showString " do\n"
                         . prettysPrec 11 body

--------------------------------------------------------------------------------
--  Running Commands
--------------------------------------------------------------------------------

data StepResult a
  = Terminated
  | Failed
  | Progress a
  deriving (Functor)

evalWhileExpr
  :: (Monad m)
  => (forall x. WhileVar l x -> m x)
  -> WhileExpr l a -> m a
evalWhileExpr f
  = fmap (runIdentity . getPureEval)
  . evalOp (fmap (PureEval . Identity) . f)

oneStep
  :: (Ord l)
  => Command l a
  -> State (Map l Integer) (StepResult (Command l a))
oneStep = \case
  CAnn ann c -> fmap (CAnn ann) <$> oneStep c

  CSeq c1 c2 ->
    do s <- oneStep c1
       case s of
         Terminated -> return (Progress c2)
         Failed -> return Failed
         Progress c1' -> return (Progress (c1' `CSeq` c2))

  CSkip -> return Terminated

  CAssign loc expr ->
    do env <- get
       if Map.member loc env then
         case evalWhileExpr (lookupVar env) expr of
           Just val ->
             do at loc .= Just val
                return Terminated
           Nothing -> return Failed
         -- Can't assign a memory location that doesn't exist
         else return Failed

  CIf cond c1 c2 ->
    do env <- get
       case evalWhileExpr (lookupVar env) cond of
         Just True -> return (Progress c1)
         Just False -> return (Progress c2)
         _ -> return Failed

  CWhile cond body ->
    do env <- get
       case evalWhileExpr (lookupVar env) cond of
         Just True -> return (Progress (body `CSeq` (CWhile cond body)))
         Just False -> return Terminated
         _ -> return Failed


runCommand :: (Ord l) => Command l a -> State (Map l Integer) Bool
runCommand command =
  do s <- oneStep command
     case s of
       Terminated -> return True
       Failed -> return False
       Progress command' -> runCommand command'

--------------------------------------------------------------------------------
--  Combinators
--------------------------------------------------------------------------------

(...) :: (c -> d) -> (a -> b -> c) -> a -> b -> d
(f ... g) x y = f (g x y)

lookupVar :: (Ord l) => Map l Integer -> WhileVar l a -> Maybe a
lookupVar env (WhileVar s) = Map.lookup s env
