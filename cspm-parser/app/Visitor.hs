module Visitor (visitFile) where

import CSPM
import CSPM.Syntax.AST
import Control.Monad.IO.Class (MonadIO(liftIO))
import Util.Annotated
import Text.Pretty.Simple (pShow, pPrint)
import qualified Data.Text.Lazy as TL
import qualified Data.ByteString.Char8 as B
import CSPM.Syntax.Literals (Literal)

type Id = UnRenamedName
data Definitions = Chan [B.ByteString] Int | Proc String | Func String | Assr String | E Expression | Pass
    deriving (Show)
data Expression = DotOperator [Expression] | L Literal | Generic String
    deriving (Show)

visitFile :: PCSPMFile -> IO [Definitions]
visitFile (An { inner = CSPMFile decls }) =
    mapM (visitDecl . unAnnotate) decls

visitDecl :: Decl Id -> IO Definitions

visitDecl (Channel names mExp mType) =
    visitChannel names mExp mType

visitDecl (PatBind pat expr mType) =
    visitPatBind (unAnnotate pat) (unAnnotate expr) mType

visitDecl (Assert assertion) =
    visitAssertion assertion

visitDecl (FunBind fun expr mType) =
    visitFunBind fun (map unAnnotate expr) mType

visitDecl a =
    notImplemented a

visitAssertion :: AnAssertion Id -> IO Definitions
visitAssertion (An { inner = PropertyCheck
    { propertyCheckProcess = proc
    , propertyCheckProperty = prop
    , propertyCheckModel = model
    , propertyCheckModelOptions = opts
    } }) = do
    -- proc' <- visitExp proc
    return $ Assr "test"

visitPatBind :: Pat Id
             -> Exp Id
             -> Maybe (AnSTypeScheme Id)
             -> IO Definitions
visitPatBind pat expr scheme = do
    -- pat' <- visitPat pat
    -- expr' <- visitExp expr
    return $ Proc "test2"

visitFunBind :: Id
             -> [Match Id]
             -> Maybe (AnSTypeScheme Id)
             -> IO Definitions
visitFunBind fun matches scheme = do
    return $ Func "sla"

visitChannel :: [Id]
    -> Maybe (AnExp Id)
    -> Maybe (AnSTypeScheme Id)
    -> IO Definitions
visitChannel ids Nothing _ = return $ Chan (map extractName ids) 0
visitChannel ids (Just expr) _ = do
    expr' <- visitExpUnAnnotate expr
    case expr' of
        DotOperator l -> return $ Chan (map extractName ids) (length l)
        _ -> return $ Chan (map extractName ids) 1

visitExpUnAnnotate :: Monad m => AnExp Id -> m Expression
visitExpUnAnnotate = visitExp . unAnnotate

extractName (UnQual (OccName name)) = name
extractName name = notImplemented name

visitExp :: Monad m => Exp Id -> m Expression
visitExp DotApp {dotAppLeftArgument=lhs, dotAppRighArgument=rhs} = do
    rhs' <- visitExpUnAnnotate rhs
    lhs' <- visitExpUnAnnotate lhs
    return $ case rhs' of
        DotOperator l -> DotOperator (lhs' : l)
        res -> DotOperator [lhs', res]
visitExp Lit {litLiteral=l} = do
    return $ Visitor.L l
visitExp Set {setItems=set} = do
    set' <- mapM visitExpUnAnnotate set
    return $ Generic "set"
visitExp App {appFunction=fun, appArguments=args} = do
    fun' <- visitExpUnAnnotate fun
    args' <- mapM (visitExp . unAnnotate) args
    return $ Generic "app"
visitExp SetEnumFromTo {setEnumFromToLowerBound=lower, setEnumFromToUpperBound=upper} = do
    return $ Generic "from to"
visitExp BooleanUnaryOp {unaryBooleanOpOperator=op, unaryBooleanExpression=expr} = do
    expr' <- visitExp (unAnnotate expr)
    return $ Generic "bool unary"
visitExp Concat {concatLeftList=lhs, concatRightList=rhs} = do
    lhs' <- visitExp (unAnnotate lhs)
    rhs' <- visitExp (unAnnotate rhs)
    return $ Generic "concat"

visitExp a = notImplemented a

notImplemented x =
    let s = pShow x in
    error ("\nNot implemented:\n" ++ TL.unpack s)
