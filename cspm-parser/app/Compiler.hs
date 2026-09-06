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

data DataReplaceable = DR (T.Text -> T.Text)
instance Show DataReplaceable where
    show (DR f) = T.unpack $ f "%data%"
getValDR :: DataReplaceable -> T.Text
getValDR (DR f) = f ""
textToDR :: T.Text -> DataReplaceable
textToDR s = DR $ \x -> s
appendToDR (DR f) s = DR (\x -> (f x) <> s)

-- Generator and related functions
data Generator = Generator {
    text :: Builder, -- The compiled text accumulator
    indent :: T.Text, -- Indentation helper
    cur :: [DataReplaceable], -- Temporary texts to help formatting at appending 'text'
    mod_name :: T.Text, -- The name of the current module
    ps :: Int, -- Parent state
    cs :: Int, -- Current state
    ns :: Int, -- Next state
    seed :: Int -- State generator
}
    deriving (Show)
newGen = Generator {text="", indent="", cur=[], mod_name = "", ps = 0, cs = 0, ns = 1, seed = 1}

clearStates :: Generator -> Generator
clearStates gen = gen{ps = 0, cs = 0, ns = 1, seed = 1}
getStates gen = (ps gen, cs gen, ns gen, seed gen)

onNextState :: Generator -> Generator
onNextState gen @ Generator {ps=_ps, cs=_cs, ns=_ns, seed=_seed} = gen{ps=_cs, cs=_ns, ns=_seed+1, seed=_seed+1}

appendText :: Generator -> T.Text -> Generator
appendText gen s = gen { text = text gen <> fromText s }

appendIndentedText :: Generator -> T.Text -> Generator
appendIndentedText gen s = gen { text = text gen <> (fromText $ indent gen) <> (fromText s) }

appendCur :: Generator -> DataReplaceable -> Generator
appendCur gen s = gen { cur = s : (cur gen) }

appendIndentedCur :: Generator -> DataReplaceable -> Generator
appendIndentedCur gen (DR f) = gen { cur = (DR $ \x -> indent gen <> (f x)) : (cur gen)  }

consumeCur :: Generator -> Generator
consumeCur (gen @ (Generator {cur=(DR f):tl,text=t})) = gen { cur = tl, text = t <> (fromText $ f "") }
consumeCur gen = gen

consumeAllCur :: Generator -> Generator
consumeAllCur (gen @ (Generator {cur=l,text=t})) = gen { cur = [], text = t <> (fromText $ T.concat $ map (\(DR f) -> f "") $ reverse l) }

takeCur (gen @ (Generator {cur=h:tl})) = (h, gen { cur=tl })

createChannelCallDR :: T.Text -> T.Text -> T.Text -> T.Text -> DataReplaceable
createChannelCallDR fn cn pst cst =
    DR $ \case "" -> sformat (stext%"(@"%stext%","%stext%","%stext%",{@next_state,"%stext%",data})") fn cn pst cst cst
               x  -> sformat (stext%"(@"%stext%","%stext%","%stext%",{@next_state,"%stext%","%stext%"})") fn cn pst cst cst x
createStateParamsDR :: T.Text -> T.Text -> DataReplaceable
createStateParamsDR event cst =
    DR $ \case "" -> sformat ("|(@cast,"%stext%","%stext%",data) ") event cst
               x  -> sformat ("|(@cast,"%stext%","%stext%","%stext%") ") event cst x

increaseTab :: Generator -> Generator
increaseTab gen = gen { indent = "\t" <> indent gen }

decreaseTab :: Generator -> Generator
decreaseTab gen = gen { indent = T.tail $ indent gen }

getStateText :: (Generator -> Int) -> Generator -> T.Text
getStateText f gen = "@" <> mod_name gen <> (T.pack $ show $ f gen)

compileDefinitions :: Monad m => [Definitions] -> m String
compileDefinitions defs = do
    g <- foldlM compileDefs (newGen { indent="" }) defs
    return $ T.unpack $ toStrict $ toLazyText $ text g

compileDefs :: Monad m => Generator -> Definitions -> m Generator
compileDefs gen (Proc pat expr) = do
    proc_name <- compilePatt pat
    let hasArrow = case expr of
            Seq _ -> "=> "
            _ -> ""
    let gen' = clearStates $ gen{mod_name=proc_name}
    let gen'' = appendText gen' $ sformat ("mod " % stext % "(@gen_statem) {\n\
      \\tpub fn create = (args) => gen_statem:start_link(@" % stext % ", args, [])\n\
      \\tpub fn callback_mode = () => @handle_event_function\n\
      \\tpub fn init = (args) => {@ok, @" % stext % "0, #{@queue = #{}}}\n\
      \\tpub fn handle_event =\n\t(@cast,@start,"%stext%",data) "%stext) proc_name proc_name proc_name (getStateText ps gen') hasArrow
    gen''' <- consumeAllCur <$> compileExpr (increaseTab $ gen'') expr
    return $ appendText gen'''
        "\n\t|(event_type, msg <- {event, original_state}, wrong_state, data <- #{@queue: q}) =>\n\
        \\t\t  {@keep_state, csp_utils:add_to_state_queue(original_state, msg, data)}\n}\n"
-- \\t\t  _=io:format(\"Received the event ('~p', '~p') of type '~p' at state '~p'.\\n\", [event, original_state, event_type, wrong_state]);\n\
compileDefs gen def = return gen

compileExpr :: Monad m => Generator -> Expression -> m Generator
compileExpr gen (ExtCh exprs) = do
    let pst = getStateText ps gen
    let cst = getStateText cs gen
    let nst = getStateText ns gen
    g <- foldlM (aux (ps gen, cs gen, ns gen)) (
        foldl appendIndentedText (appendText gen "{\n") [
            "#{@queue: q} = data;\n",
            "match q\n",
            (sformat
                ("| (#{"%stext%": h :: tl}) => {@next_state,"%stext%", data#{@queue = q#{"%stext%" = tl}}, [{@next_event, @cast, h}]}\n")
                pst cst pst),
            "|(_) {\n"]) exprs
    return $ consumeAllCur $
        appendIndentedText (appendIndentedText g "}\n") (
            sformat ("}|(@cast, event <- {_,"%stext%"},"%stext%",data) => {@next_state,"%stext%", data, [{@next_event, @cast, event}]}\n")
                pst pst nst)
    where
        aux (_ps, _cs, _ns) gen (Seq (h:tl)) = do
            -- use the next state from the external choice, but them backup the most recent one (ns')
            let Generator {ns=ns'} = gen
            (g, msg, next_state) <- compileEvent gen{ps=_ps, cs=_cs, ns=_ns} h
            let g' = appendIndentedCur (appendIndentedText g{ns=ns', seed=ns'} ("_=" <> (getValDR msg) <> ";\n")) $ DR $ \_ -> (getValDR next_state) <> "=> "
            compileExpr g' (Seq tl)

compileExpr gen (Seq seq) = do
    foldlM compileExpr gen seq
compileExpr gen (event @ (Event _ _)) = do
    (g, msg, next_state) <- compileEvent gen event
    return $ appendIndentedCur (appendCur g $ appendToDR msg "\n") $ appendToDR next_state "=> "
compileExpr gen (V "STOP") = do
    return $ appendCur gen $ textToDR "{@next_state, @stop, data}\n"
compileExpr gen (V "SKIP") = do
    return $ appendCur gen $ textToDR "{@next_state, @skip, data}\n"
compileExpr gen (V s) = do
    return $ appendCur gen (textToDR $ decodeUtf8 s)
compileExpr gen (L l) = do
    s <- compilePatt (PatL l)
    return $ appendCur gen $ textToDR s
compileExpr gen expr =
    return $ appendIndentedCur gen (textToDR $ T.show expr)

compileEvent :: Monad m => Generator -> Expression -> m (Generator, DataReplaceable, DataReplaceable)
compileEvent gen (Event expr fields) = do
    let g = onNextState gen
    pTraceShowM (expr, getStates g)
    let ng = newGen
    chan <- compileExpr ng expr
    fields' <- mapM (compileInOut ng) fields
    let cn = getValDR $ fst $ takeCur chan
    let pst = getStateText ps g
    let cst = getStateText cs g
    let nst = getStateText ns g
    let event = sformat ("{@" %stext% ", " %stext% "}") cn pst
    let (args, branch) = aux fields' cn pst cst
    -- let (recv, send) = unzip fields'
    return (g, args, branch)
    -- if all isNothing recv
    -- then
    -- else
    --     return $ appendIndentedCur gen $ sformat ("{" % stext % "} = env(@" % stext % ", {" % stext % "});\n")
    --         (T.intercalate ", " $ map (\case
    --             Just p -> p
    --             Nothing -> "{}") recv)
    --         (cur chan) (T.intercalate ", " send)
    where
        aux [] cn pst cst =
            let event = sformat ("{@" %stext% ", " %stext% "}") cn pst in
            (createChannelCallDR "csp_channel:event" cn pst cst, createStateParamsDR event cst)
        aux (params @ ((Nothing, _):_)) cn pst cst =
            let fn_call = "csp_channel:send" in 
            let event = sformat ("{@"%stext%","%stext%"}") cn pst in
            (createChannelCallDR fn_call cn pst cst, createStateParamsDR event cst)
        aux (params @ ((Just _, _):_)) cn pst cst =
            let fn_call = "csp_channel:recv" in
            let event = sformat ("{@"%stext%","%stext%",{"%stext%"}}") cn pst (T.intercalate "," (paramsIntoList params)) in
            (createChannelCallDR fn_call cn pst cst, createStateParamsDR event cst)

        paramsIntoList :: [(Maybe T.Text, T.Text)] -> [T.Text]
        paramsIntoList [] = []
        paramsIntoList ((Nothing, val):tl) = val : (paramsIntoList tl)
        paramsIntoList ((Just val, "@recv"):tl) = val : (paramsIntoList tl)

        compileInOut :: Monad m => Generator -> Expression -> m (Maybe T.Text, T.Text)
        compileInOut gen (In p) = do
            s <- compilePatt p
            return $ (Just s, "@recv")
        compileInOut gen (Out expr) = do
            expr' <- compileExpr gen expr
            return $ (Nothing, getValDR $ fst $ takeCur expr')
compileEvent _ _ = error "Not expected"

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
