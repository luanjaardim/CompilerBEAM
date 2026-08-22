{-# LANGUAGE OverloadedStrings #-}
module Compiler (compileDefinitions) where

import Visitor (Definitions (Proc), Expression (..), Pattern (PatL, PatV))
import qualified Data.ByteString.Char8 as B
import Util.MonadicPrettyPrint (render, prettyPrint)
import Text.Pretty.Simple (pShow)
import Data.Foldable (foldlM)
import qualified Data.ByteString.Builder as B
import Data.List (intercalate)
import Data.Text.Lazy.Builder (Builder, fromText, toLazyText)
import qualified Data.Text as T
import qualified Data.Text.Internal.StrictBuilder as T
import Data.Text.Encoding (decodeUtf8)
import CSPM.Syntax.Literals (Literal(..))
import Control.Exception.Base (throw)
import Formatting (sformat, (%), stext)
import Util.HierarchicalMap (flatten)
import Data.Text.Internal.Builder (toLazyText)
import Data.Text.Lazy (toStrict)

-- Generator and related functions
data Generator = Generator {
    text :: Builder, -- The compiled text accumulator
    prefix :: Builder, -- Text that must be written before 'text'
    indent :: T.Text, -- Indentation helper
    cur :: T.Text -- Temporary texts to help formatting at appending 'text'
}
appendText :: Generator -> T.Text -> Generator
appendText gen s = gen { text = text gen <> (fromText $ indent gen) <> (fromText s) }

appendPrefix :: Generator -> T.Text -> Generator
appendPrefix gen s = gen { prefix = prefix gen <> fromText s }

appendToCur :: Generator -> T.Text -> Generator
appendToCur gen s = gen { cur = cur gen <> s }

increaseTab :: Generator -> Generator
increaseTab gen = gen { indent = "\t" <> indent gen }

decreaseTab :: Generator -> Generator
decreaseTab gen = gen { indent = T.tail $ indent gen }

compileDefinitions :: Monad m => [Definitions] -> m String
compileDefinitions defs = do
    Generator {text=t, prefix=p} <- foldlM compileDefs (Generator {text="", prefix="", indent="\t\t", cur=""}) defs
    return $ T.unpack $ toStrict $ toLazyText $ p <> t

compileDefs :: Monad m => Generator -> Definitions -> m Generator
compileDefs gen (Proc pat expr) = do
    pat' <- compilePatt pat
    let gen' = increaseTab $ appendText gen (pat' <> " =| {\n")
    gen'' <- decreaseTab <$> compileExpr gen' expr
    return $ appendText gen'' "}\n"
compileDefs gen def = return gen

compileExpr :: Monad m => Generator -> Expression -> m Generator
compileExpr gen (Seq seq) = do
    foldlM compileExpr gen seq
compileExpr gen (Event expr fields) = do
    chan <- compileExpr gen expr
    fields' <- mapM (compileExpr gen) fields
    let params = map cur fields'
    let t = sformat ("chan(@" % stext % ", {" % stext % "});\n") (cur chan) (T.intercalate ", " params)
    return $ appendText gen t
    -- foldlM compileExpr chan fields
compileExpr gen (In p) = do
    s <- compilePatt p
    return $ appendToCur gen s
compileExpr gen (Out expr) = compileExpr gen expr
compileExpr gen (V "STOP") = do
    return $ appendText gen "@stop\n"
compileExpr gen (V "SKIP") = do
    return $ appendText gen "@skip\n"
compileExpr gen (V s) = do
    return $ appendToCur gen (decodeUtf8 s)
compileExpr gen (L l) = do
    s <- compilePatt (PatL l)
    return $ appendToCur gen s
compileExpr gen expr =
    return $ appendToCur gen (T.show expr)

compilePatt :: Monad m => Pattern -> m T.Text
compilePatt (PatL l) = return $ literalToText l
compilePatt (PatV s) = return $ decodeUtf8 s

literalToText :: Literal -> T.Text
literalToText lit = case lit of
    Int n -> T.pack (show n)
    Bool b -> if b then "true" else "false"
    Char c   -> T.singleton c
    String s -> decodeUtf8 s
    _ -> error "Literal Loc"
