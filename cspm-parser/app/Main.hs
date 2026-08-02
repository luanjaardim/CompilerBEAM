import CSPM
import qualified CSPM.CommandLineOptions as CSPM
import Control.Monad.IO.Class (MonadIO(liftIO))
import Text.Pretty.Simple (pPrint)
import System.Environment (getArgs)

main = do
    files <- getArgs
    session <- newCSPMSession defaultEvaluatorOptions

    unCSPM session $ do
        CSPM.setOptions CSPM.defaultOptions
        parsed <- parseFile $ head files
        liftIO $ pPrint parsed
        renamed <- CSPM.renameFile parsed
        typed <- typeCheckFile renamed

        liftIO $ putStrLn "Successfully parsed and typechecked."

