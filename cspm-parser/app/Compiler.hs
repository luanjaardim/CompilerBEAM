{-# LANGUAGE OverloadedStrings #-}
module Compiler (compileDefinitions) where

import Visitor (Definitions (Proc), Expression (V, Seq, Event), Pattern (PatL, PatV))
import qualified Data.Text.Lazy as TL
import qualified Data.ByteString.Char8 as B
import CSPM.Syntax.Literals (Literal)
import Util.MonadicPrettyPrint (render, prettyPrint)
import Text.Pretty.Simple (pShow)
import Data.Foldable (foldlM)
import qualified Data.ByteString.Builder as B

-- Generator and related functions
data Generator = Generator {
    text :: String,
    prefix :: String,
    indent :: String
}
appendText :: Generator -> String -> Generator
appendText gen s = gen { text = text gen ++ indent gen ++ s }

appendPrefix :: Generator -> String -> Generator
appendPrefix gen s = gen { prefix = prefix gen ++ s }

increaseTab :: Generator -> Generator
increaseTab gen = gen { indent = '\t' : indent gen }

decreaseTab :: Generator -> Generator
decreaseTab gen = gen { indent = tail $ indent gen }

compileDefinitions :: Monad m => [Definitions] -> m String 
compileDefinitions defs = do
    gen' <- foldlM compileDefs (Generator {text="", prefix="", indent="\t\t"}) defs
    case gen' of Generator {text=t, prefix=p} -> return $ p ++ t

compileDefs :: Monad m => Generator -> Definitions -> m Generator
compileDefs gen (Proc pat expr) = do
    pat' <- compilePatt pat
    gen' <- increaseTab <$> pure (appendText gen (pat' ++ " =| {\n"))
    gen'' <- decreaseTab <$> compileExpr gen' expr
    return $ appendText gen'' "}\n"
compileDefs gen def = return gen

compileExpr :: Monad m => Generator -> Expression -> m Generator
compileExpr gen (Seq seq) = do
    foldlM compileExpr gen seq
compileExpr gen (Event expr fields) = do
    chan <- compileExpr gen expr
    foldlM compileExpr chan fields
compileExpr gen (V "STOP") = do
    return $ appendText gen "@stop\n"
compileExpr gen (V "SKIP") = do
    return $ appendText gen "@skip\n"
compileExpr gen (V s) = do
    return $ appendText gen (B.unpack s)
compileExpr gen expr =
    return $ appendText gen (show expr)

compilePatt :: Monad m => Pattern -> m String
compilePatt (PatL l) = return $ (tail . init) $ show $ pShow l
compilePatt (PatV s) = return $ B.unpack s
