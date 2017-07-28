{-# LANGUAGE LambdaCase #-}

module Language.While.Hoare.Prover where

import           Language.Verification                      (Location, Verifier,
                                                             VerifierError,
                                                             checkProp,
                                                             runVerifier)
import qualified Language.Verification.Expression           as V
import qualified Language.Verification.Expression.Operators as V
import Language.Verification.Expression.DSL

import           Language.While.Hoare


provePartialHoare
  :: Location l
  => WhileProp l
  -> WhileProp l
  -> AnnCommand l a
  -> Verifier l (V.Expr V.BasicOp) Bool
provePartialHoare precond postcond cmd =
  do vcs <- case generateVCs precond postcond cmd of
              Just x -> return x
              Nothing -> fail "Command not sufficiently annotated"

     let bigVC = foldr (*&&) (plit True) vcs

     checkProp bigVC

provePartialHoare'
  :: Location l
  => WhileProp l
  -> WhileProp l
  -> AnnCommand l a
  -> IO (Either (VerifierError l (V.Expr V.BasicOp)) Bool)
provePartialHoare' precond postcond cmd = runVerifier (provePartialHoare precond postcond cmd)
