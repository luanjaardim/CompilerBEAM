{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE LambdaCase #-}
module Compiler (compileDefinitions) where

import Visitor (Definitions (Proc, Func, Clause), Expression (..), Pattern (PatL, PatV))
import qualified Data.ByteString.Char8 as B
import Util.MonadicPrettyPrint (render, prettyPrint)
import Text.Pretty.Simple (pShow)
import Data.Foldable (foldlM)
import qualified Data.ByteString.Builder as B
import Data.List (intercalate, (\\), nub)
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
import Text.Regex.TDFA ((=~))
import Text.Regex.TDFA.Text ()

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
    cur :: [DataReplaceable], -- Temporary texts to help formatting at appending 'text'
    mod_name :: T.Text, -- The name of the current module
    tmp_params :: [T.Text],
    ps :: Int, -- Parent state
    cs :: Int, -- Current state
    ns :: Int, -- Next state
    seed :: Int -- State generator
}
    deriving (Show)
newGen = Generator {text="", cur=[], tmp_params=[], mod_name = "", ps = 0, cs = 0, ns = 1, seed = 1}

clearStates :: Generator -> Generator
clearStates gen = gen{ps = 0, cs = 0, ns = 1, seed = 1}
getStates gen = (ps gen, cs gen, ns gen, seed gen)

onNextState :: Generator -> Generator
onNextState gen @ Generator {ps=_ps, cs=_cs, ns=_ns, seed=_seed} = gen{ps=_cs, cs=_ns, ns=_seed+1, seed=_seed+1}

appendText :: Generator -> T.Text -> Generator
appendText gen s = gen { text = text gen <> fromText s }

appendCur :: Generator -> DataReplaceable -> Generator
appendCur gen s = gen { cur = s : (cur gen) }

consumeCur :: Generator -> Generator
consumeCur (gen @ (Generator {cur=(DR f):tl,text=t})) = gen { cur = tl, text = t <> (fromText $ f "") }
consumeCur gen = gen

consumeCurWithArg :: Generator -> T.Text -> Generator
consumeCurWithArg (gen @ (Generator {cur=(DR f):tl,text=t})) arg = gen { cur = tl, text = t <> (fromText $ f arg) }
consumeCurWithArg gen _ = gen

consumeAllCur :: Generator -> Generator
consumeAllCur (gen @ (Generator {cur=l,text=t})) = gen { cur = [], text = t <> (fromText $ T.concat $ map (\(DR f) -> f "") $ reverse l) }

takeCur (gen @ (Generator {cur=h:tl})) = (h, gen { cur=tl })

createChannelCallDR :: T.Text -> T.Text -> T.Text -> T.Text -> T.Text -> DataReplaceable
createChannelCallDR fn cn pst cst d =
    DR $ \case "" -> sformat (stext%"(@"%stext%","%stext%","%stext%","%stext%"{@next_state,"%stext%",data})") fn cn pst cst d cst
               x  -> sformat (stext%"(@"%stext%","%stext%","%stext%","%stext%"{@next_state,"%stext%","%stext%"})") fn cn pst cst d cst x
createStateParamsDR :: T.Text -> T.Text -> DataReplaceable
createStateParamsDR event cst =
    DR $ \case "" -> sformat ("\t|(@cast,"%stext%","%stext%",data) ") event cst
               x  -> sformat ("\t|(@cast,"%stext%","%stext%","%stext%") ") event cst x

getStateText :: (Generator -> Int) -> Generator -> T.Text
getStateText f gen = "@" <> mod_name gen <> (T.pack $ show $ f gen)

compileDefinitions :: Monad m => [Definitions] -> m String
compileDefinitions defs = do
    g <- foldlM compileDefs newGen defs
    return $ T.unpack $ toStrict $ toLazyText $ text g

compileDefs :: Monad m => Generator -> Definitions -> m Generator
compileDefs gen (Proc pat expr) = do
    pn <- compilePatt pat -- proc_name
    let gen' = appendCur (consumeCurWithArg gen{cur=[prefixDR pn]} "@start") $ DR $ \arrow -> "(@cast,@start,@"<>pn<>"0,data) "<>arrow
    g <- compileBody (clearStates gen') pn [] expr
    return $ appendText g suffixHandleEvent
compileDefs gen (Func mn defs) = do
    let mn' = decodeUtf8 mn
    let gen' = clearStates $ appendCur gen{mod_name=mn'} $ prefixDR mn'
    g <- foldlM (\g d -> compileDefs g{ps=ps gen',cs=cs gen'} d) gen' defs
    return $ appendText g suffixHandleEvent
compileDefs gen (Clause params body) = do
    params' <- mapM (\x -> mapM compilePatt x) params
    -- WARNING: At the moment only one list of params is accepted
    let p = head params'
    let vars = filterNames p
    let event_params = "{" <> (T.intercalate "," p) <> "}"
    let branch = DR $ \arrow -> sformat (stext%"(@cast,{@start,"%stext%"},@"%stext%"0,data) "%stext)
           (case cur gen of
                ((DR f):_) -> f ("{@start,args}")
                [] -> "\t|"
           ) event_params (mod_name gen) arrow
    compileBody gen{cur=[branch], tmp_params=vars} (mod_name gen) p body
compileDefs gen def = return gen

compileBody :: Monad m => Generator -> T.Text -> [T.Text] -> Expression -> m Generator
compileBody gen mn params body = do
    let gen' = gen{mod_name = mn}
    let hasArrow = case body of
            ExtCh _ -> ""
            _ -> "=> "
    consumeAllCur <$> compileExpr (consumeCurWithArg gen' hasArrow) body

compileExpr :: Monad m => Generator -> Expression -> m Generator
compileExpr gen (ExtCh exprs) = do
    let pst = getStateText ps gen
    let cst = getStateText cs gen
    let nst = getStateText ns gen
    let gen' = consumeAllCur gen
    g <- foldlM (aux (ps gen', cs gen', ns gen')) (
        foldl appendText (appendText gen' "{\n") [
            "\t\t#{@queue: q} = data;\n",
            "\t\tmatch q\n",
            (sformat
                ("\t\t| (#{"%stext%": h :: tl}) => {@next_state,"%stext%", data#{@queue = q#{"%stext%" = tl}}, [{@next_event, @cast, h}]}\n")
                pst cst pst),
            "\t\t|(_) {\n"]) exprs
    return $ consumeAllCur $
        appendText (appendText g "\t\t}\n") (
            sformat ("\t}|(@cast, event <- {_,"%stext%"},"%stext%",data) => {@next_state,"%stext%", data, [{@next_event, @cast, event}]}\n")
                pst pst nst)
    where
        aux (_ps, _cs, _ns) gen (Seq (h:tl)) = do
            -- use the next state from the external choice, but them backup the most recent one (ns')
            let Generator {ns=ns'} = gen
            (g, msg, next_state) <- compileEvent gen{ps=_ps, cs=_cs, ns=_ns, tmp_params=[]} h
            let g' = appendCur (appendText g{ns=ns', seed=ns'} ("\t\t\t_=" <> (getValDR msg) <> ";\n")) $ DR $ \_ -> (getValDR next_state) <> "=> "
            compileExpr g' (Seq tl)

compileExpr gen (Seq seq) = do
    foldlM compileExpr gen seq
compileExpr gen (event @ (Event _ _)) = do
    (g, msg, next_state) <- compileEvent gen event
    return $ appendCur (appendCur g $ appendToDR msg "\n") $ appendToDR next_state "=> "
compileExpr gen (FuncApp (V fn_name) args) = do
    gen_args <- foldlM compileExpr gen{cur=[]} args
    let args = map (\(DR f) -> f "") $ reverse $ cur gen_args
    let args_from_data = nub $ filterNames args
    let gen' = case cur gen of
            (h:tl) -> gen{cur=(dataWithParams h args_from_data ":"):tl}
            [] -> gen
    return $ appendCur gen' $ textToDR $ (decodeUtf8 fn_name) <> ":enter({"<> (T.intercalate "," args)<> "})\n"
compileExpr gen (ProcCall (V "STOP")) = do
    return $ appendCur gen $ textToDR "{@next_state, @stop, data}\n"
compileExpr gen (ProcCall (V "SKIP")) = do
    return $ appendCur gen $ textToDR "{@next_state, @skip, data}\n"
compileExpr gen (ProcCall (V n)) = do
    return $ appendCur gen $ textToDR $ (decodeUtf8 n) <> ":enter(@none)\n"
compileExpr gen (V s) = do
    return $ appendCur gen $ textToDR $ decodeUtf8 s
compileExpr gen (L l) = do
    s <- compilePatt (PatL l)
    return $ appendCur gen $ textToDR s
compileExpr gen expr =
    return $ appendCur gen (textToDR $ T.show expr)

compileEvent :: Monad m => Generator -> Expression -> m (Generator, DataReplaceable, DataReplaceable)
compileEvent gen (Event expr params) = do
    let g = onNextState gen
    let ng = newGen
    chan <- compileExpr ng expr
    params' <- mapM (compileInOut ng) params
    let cur_params = paramsIntoList params'
    let cn = getValDR $ fst $ takeCur chan
    let pst = getStateText ps g
    let cst = getStateText cs g
    let nst = getStateText ns g
    let event = sformat ("{@" %stext% ", " %stext% "}") cn pst
    let (channel_call, branch) = aux params' cn pst cst
    let channel_call' = case tmp_params g of
            [] -> channel_call
            _  -> dataWithParams channel_call (tmp_params g) "="
    let ps = paramsIntoList params'
    case params of
        ((In _):_)  -> -- Receiving from a channel
            return (g { tmp_params = paramsIntoList params' }, channel_call', branch)
        ((Out _):_) -> -- Sending valus to a channel
            let ps = paramsIntoList params' in
            let g' = case (filterNames ps, cur g) of
                    ((_:_), (_:_)) ->
                            let (prev_branch, g') = takeCur g in
                            let req_data = dataWithParams prev_branch (ps \\ (tmp_params g)) ":" in
                            appendCur g' req_data
                    (_,_)  -> g
            in return (g' { tmp_params = [] }, channel_call', branch)
        _ -> -- Event
            return (g { tmp_params = [] }, channel_call', branch)
    where
        aux [] cn pst cst =
            let event = sformat ("{@" %stext% ", " %stext% "}") cn pst in
            (createChannelCallDR "csp_channel:event" cn pst cst "", createStateParamsDR event cst)
        aux (params @ ((Nothing, _):_)) cn pst cst =
            let fn_call = "csp_channel:send" in
            let event = sformat ("{@"%stext%","%stext%"}") cn pst in
            (createChannelCallDR fn_call cn pst cst ("{"<>(T.intercalate "," (paramsIntoList params))<>"},"), createStateParamsDR event cst)
        aux (params @ ((Just _, _):_)) cn pst cst =
            let fn_call = "csp_channel:recv" in
            let event = sformat ("{@"%stext%","%stext%",{"%stext%"}}") cn pst (T.intercalate "," (paramsIntoList params)) in
            (createChannelCallDR fn_call cn pst cst "", createStateParamsDR event cst)

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

filterNames :: [T.Text] -> [T.Text]
filterNames params = filter (\x -> x =~ ("^[a-zA-Z][a-zA-Z0-9_]*$" :: String)) params

dataWithParams dr [] op = dr
dataWithParams (dr @ (DR f)) params (op @ "=") =
    let values = T.intercalate "," $ map (\y -> "@"<>y<>op<>y) $ nub $ filterNames params in
    case values of
            "" -> dr
            _ -> DR $ \_ -> f ("data#{" <> values <> "}")
dataWithParams (DR f) params op =
    let values = T.intercalate "," $ map (\y -> "@"<>y<>op<>y) $ nub $ filterNames params in
    DR $ \_ -> f ("data <- #{" <> values <> "}")


prefixDR mod_name = DR $ \event -> sformat ("mod " % stext % "(@gen_statem) {\n\
          \\tpub fn create = (args) => gen_statem:start_link(@"%stext%", args, [])\n\
          \\tpub fn enter = (args) => gen_statem:enter_loop(@"%stext%", [], @"%stext%"0, #{@queue = #{}}, [{@next_event, @cast, "%stext%"}])\n\
          \\tpub fn callback_mode = () => @handle_event_function\n\
          \\tpub fn init = (args) => {@ok, @" % stext % "0, #{@queue = #{}}}\n\
          \\tpub fn handle_event =\n\t") mod_name mod_name mod_name mod_name event mod_name

suffixHandleEvent =
        "\t|(event_type, msg <- {event, original_state}, wrong_state, data <- #{@queue: q}) =>\n\
        \\t\t  {@keep_state, csp_utils:add_to_state_queue(original_state, msg, data)}\n}\n"

literalToText :: Literal -> T.Text
literalToText lit = case lit of
    Int n -> T.pack (show n)
    Bool b -> if b then "true" else "false"
    Char c   -> T.singleton c
    String s -> decodeUtf8 s
    _ -> error "Literal Loc"
