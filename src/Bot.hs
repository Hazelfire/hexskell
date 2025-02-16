module Bot where

import Hex

import Data.List
import Data.Maybe
import System.Process
import System.IO
import System.Exit
import Text.Regex
import Text.Read

data BotArgument = None | BotArgument (Checkers, Checkers) BotArgument -- friendly, enemy, previous game state
data BotError = BotError String
type Bot = BotArgument -> Checker -- game state -> new piece
type Bots = (Bot, Bot) --red, blue

-- gamestate is transformed recursively such that friendly checkers are passed first and so that board is transposed for blue
botArgument :: Allegiance -> GameState -> BotArgument
botArgument allegiance (Initial) = None
botArgument allegiance (Ongoing (red, blue) previous) =
  if allegiance == Red
    then BotArgument (red, blue) (botArgument allegiance previous)
    else BotArgument (both transposeCoordinates (blue, red)) (botArgument allegiance previous)

botError :: String -> BotError
botError message = BotError message

-- placeholder bot (just returns first empty hex)
phBot :: Bot
--phBot (None) =  -- Need to come up with a solution for here, perhaps bots can return a special 'BotError' type?
phBot (BotArgument (friendly, enemy) previous) =
  head $ filter empty $ allCheckers
  where
    empty = (not . positionHasChecker (friendly, enemy))

toExternalCheckersString :: Checkers -> String
toExternalCheckersString checkers = concat $ intersperse "|" $ map (\(x, y) -> show x ++ "," ++ show y) checkers

fromExternalCheckerString :: String -> Maybe Checker
fromExternalCheckerString str = readMaybe ("(" ++ str ++ ")") :: Maybe Checker

scriptFromTemplate :: String -> String -> String
scriptFromTemplate template code =
  (subRegex
    (mkRegex "\\/\\*\\s*BOT-START\\s*\\*\\/([\\s\\S]*)\\/\\*\\s*BOT-END\\s*\\*\\/")
    template
    code
  )

isValidNewChecker :: BotArgument -> Checker -> Bool
isValidNewChecker arg@(BotArgument bs@(friendly, enemy) _) checker = all ($ checker) predicates
  where
    predicates = [validCoordinate, isAllegiance bs Neutral]

-- requires 'node' in PATH & 'bot-template.js' in cd
runExternalBot :: String -> BotArgument -> IO (Either Checker BotError) --String -> BotArgument -> IO (Maybe Coordinate)
runExternalBot botJS arg@(BotArgument (friendly, enemy) previous) = do
  -- read template
  template <- readFile templatePath

  -- sub in program js code
  let fullScript = scriptFromTemplate template botJS

  -- run external process
  (exitCode, out, err) <- readProcessWithExitCode command arguments template

  -- parse output to a checker
  let checker = fromExternalCheckerString out

  -- was there an error / return approp value?
  return (case exitCode of
    ExitFailure _ -> Right (BotError err) -- probably add more detail later and stuff
    ExitSuccess -> case checker of
      Nothing -> Right (BotError "Bot failed to return a checker")
      Just checker -> if isValidNewChecker arg checker
        then Left checker
        else Right (BotError ("Bot returned invalid checker " ++ show checker)))

  where
    command = "node"
    templatePath = "./bot-template.js"
    friendlyS = toExternalCheckersString friendly
    enemyS = toExternalCheckersString enemy
    arguments = ["", friendlyS, enemyS]