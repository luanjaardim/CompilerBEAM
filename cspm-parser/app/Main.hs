import CSPM
import qualified CSPM.CommandLineOptions as CSPM
import Control.Monad.IO.Class (MonadIO(liftIO))
import Text.Pretty.Simple (pPrint)
import System.Environment (getArgs)
import Visitor (visitFile)
import Compiler (compileDefinitions)
import qualified Data.Text.Lazy as TL

parseAST :: String -> IO PCSPMFile
parseAST fileName = do
    session <- newCSPMSession defaultEvaluatorOptions
    (ast, _) <- unCSPM session $ do
        CSPM.setOptions CSPM.defaultOptions

        parsed <- parseFile fileName
        renamed <- CSPM.renameFile parsed
        typeCheckFile renamed

        return parsed
    return ast

main = do
    files <- getArgs
    ast <- parseAST $ head files
    -- pPrint ast
    code <- visitFile ast
    s <- compileDefinitions code
    pPrint code
    putStrLn s
