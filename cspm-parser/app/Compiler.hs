{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE LambdaCase #-}
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
import Data.Maybe (isNothing)

-- Generator and related functions
data Generator = Generator {
    text :: Builder, -- The compiled text accumulator
    prefix :: Builder, -- Text that must be written before 'text'
    indent :: T.Text, -- Indentation helper
    cur :: T.Text -- Temporary texts to help formatting at appending 'text'
}
    deriving (Show)
newGen = Generator {text="", prefix="", indent="", cur=""}

appendText :: Generator -> T.Text -> Generator
appendText gen s = gen { text = text gen <> (fromText $ indent gen) <> (fromText s) }

appendPrefix :: Generator -> T.Text -> Generator
appendPrefix gen s = gen { prefix = prefix gen <> fromText s }

appendCur :: Generator -> T.Text -> Generator
appendCur gen s = gen { cur = cur gen <> s }

appendIndentedCur :: Generator -> T.Text -> Generator
appendIndentedCur gen s = gen { cur = cur gen <> indent gen <> s }

consumeCur :: Generator -> Generator
consumeCur gen = gen { cur = "", text = text gen <> (fromText $ cur gen) }

increaseTab :: Generator -> Generator
increaseTab gen = gen { indent = "\t" <> indent gen }

decreaseTab :: Generator -> Generator
decreaseTab gen = gen { indent = T.tail $ indent gen }

compileDefinitions :: Monad m => [Definitions] -> m String
compileDefinitions defs = do
    Generator {text=t, prefix=p} <- foldlM compileDefs (newGen { indent="" }) defs
    return $ T.unpack $ toStrict $ toLazyText $ p <> t

compileDefs :: Monad m => Generator -> Definitions -> m Generator
compileDefs gen (Proc pat expr) = do
    pat' <- compilePatt pat
    let gen' = appendText gen (sformat ("mod " % stext % "(@gen_statem) {\n\
      \\tpub fn create = (args) => gen_statem:start_link(@" % stext % ", args, [])\n\
      \\tpub fn callback_mode = () => @handle_event_function\n\
      \\tpub fn init = (args) => {@ok, @" % stext % "0, #{@args = args, @queue = #{}}, [{@next_event, @cast, @start}]}\n\
      \\tpub fn handle_event =\n") (pat') (pat') (pat'))
    gen'' <- consumeCur <$> compileExpr gen' expr
    return $ appendText (gen''{indent=""}) $ sformat ("\n\t| (event_type, msg <- {event, original_state}, wrong_state, data <- #{@queue: q}) {\n\
\\t\t  _=io:format(\"Received the event ('~p', '~p') of type '~p' at state '~p'.\\n\", [event, original_state, event_type, wrong_state]);\n\
\\t\t  {@keep_state, csp_utils:add_to_state_queue(original_state, msg, data)}\n\t}\n}")
compileDefs gen def = return gen

compileExpr :: Monad m => Generator -> Expression -> m Generator
compileExpr gen (Seq seq) = do
    foldlM compileExpr gen seq
compileExpr gen (Event expr fields) = do
    let ng = newGen
    chan <- compileExpr ng expr
    fields' <- mapM (compileInOut ng) fields
    let (recv, send) = unzip fields'
    if all isNothing recv
    then
        -- -- TODO: verify if its a channel, a function call or STOP/SKIP
        case expr of
            V "SKIP" -> return gen
            V "STOP" -> return gen
            _ -> return $ appendIndentedCur gen $ sformat ("env(@" % stext % ", {" % stext % "});\n") (cur chan) (T.intercalate ", " send)
    else
        return $ appendIndentedCur gen $ sformat ("{" % stext % "} = env(@" % stext % ", {" % stext % "});\n")
            (T.intercalate ", " $ map (\case
                Just p -> p
                Nothing -> "{}") recv)
            (cur chan) (T.intercalate ", " send)
    where
        compileInOut :: Monad m => Generator -> Expression -> m (Maybe T.Text, T.Text)
        compileInOut gen (In p) = do
            s <- compilePatt p
            return $ (Just s, "@recv")
        compileInOut gen (Out expr) = do
            expr' <- compileExpr gen expr
            return $ (Nothing, cur expr')
        
    -- foldlM compileExpr chan fields
compileExpr gen (V "STOP") = do
    return $ appendIndentedCur gen "@stop\n"
compileExpr gen (V "SKIP") = do
    return $ appendIndentedCur gen "@skip\n"
compileExpr gen (V s) = do
    return $ appendCur gen (decodeUtf8 s)
compileExpr gen (L l) = do
    s <- compilePatt (PatL l)
    return $ appendCur gen s
compileExpr gen expr =
    return $ appendIndentedCur gen (T.show expr)

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
