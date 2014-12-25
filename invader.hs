--module Main where

import Data.Ord 

import FRP.Helm
import qualified FRP.Helm.Graphics  as Graphics
import qualified FRP.Helm.Keyboard  as Keyboard
import qualified FRP.Helm.Window    as Window
import qualified FRP.Helm.Text      as Text
import qualified FRP.Helm.Color     as Color
import qualified FRP.Helm.Time      as Time


data GameConfig = GameConfig {
  windowDims :: (Int,Int),
  shipDims   :: (Int,Int),
  rocketDims :: (Int,Int),
  invaderDims :: (Int,Int)
}

data GameStatus = Startup | InProcess |Over
  deriving (Enum, Bounded,Eq)

data GameState = GameState {status :: GameStatus}

data ShipState = ShipState {shipX :: Int, shipY :: Int} 

data InvaderState = InvaderState {invaderX :: Int, invaderY :: Int, invaderM :: InvaderMovement}

data RocketState = RocketState { rocketX :: Int, rocketY :: Int, rocketFlying :: Bool}

data InvaderMovement = R|D|L|D2
   deriving (Eq)

gameConfig :: GameConfig
gameConfig = GameConfig {
      windowDims = (450,800),
      shipDims   = (70,100),
      rocketDims = (10,10),
      invaderDims = (100,100)
}


engineConfig :: GameConfig -> EngineConfig
engineConfig gameConfig = 
  EngineConfig (windowDims gameConfig) False False "Monad Invaders v0.0.1"

backgroundImg :: GameConfig -> Element
backgroundImg gameConfig = Graphics.fittedImage 
                (fst . windowDims $ gameConfig)
                (snd . windowDims $ gameConfig) "Graphics/background/paper_smashed_vertical.png"


invaderImg ::FilePath -> GameConfig -> Element
invaderImg file gameConfig = Graphics.fittedImage (fst . invaderDims $ gameConfig) (snd . invaderDims $ gameConfig) file


spaceShipImg :: GameConfig -> Element
spaceShipImg gameConfig = Graphics.fittedImage 
                (fst . shipDims $ gameConfig) 
                (snd . shipDims $ gameConfig) "Graphics/ship/ship.png"


gameSignal :: Signal GameState
gameSignal = foldp modifyState initialState (Keyboard.isDown Keyboard.SpaceKey)
  where
    initialState = GameState {status = Startup}

    --controlSignal :: Signal (Bool,(Int,Int))
    --controlSignal = lift2 (,) (Keyboard.isDown Keyboard.SpaceKey)

    modifyState :: Bool -> GameState -> GameState
    modifyState pressed state = 
      if pressed && (status state == Startup) 
      then state {status = nextStatus} 
      else state {status = status state}
      where
        nextStatus = 
          let s = status state in
          if s == (maxBound :: GameStatus) then s else succ s

invaderSignal :: Int -> Signal GameState -> Signal [InvaderState]
invaderSignal color gameSignal  = foldp modifyState  initialState controlSignal
   where 
     yPosition = case color of 
                     0 -> 0
                     1 -> 80
                     2 -> 160
     initialState = zipWith (\ n state -> state {invaderX = (fst . invaderDims $ gameConfig )*(n-1) +20 })  [1..4] 
                                               (replicate 4 $ InvaderState {invaderX = 0, invaderY = yPosition , invaderM = R})

     controlSignal :: Signal (GameState,Time,Bool)
     controlSignal = lift3 (,,) gameSignal
                     (Time.every $ 1000 * Time.millisecond)
                     (Keyboard.isDown Keyboard.SpaceKey)
     modifyState :: (GameState,Time,Bool) -> [InvaderState] -> [InvaderState]
     modifyState (gameState,time, pressed) states =
                       if (status gameState == InProcess) && not  pressed
                       then (zipWith (\n st -> f st n) [1..length states] states)
                       else states
		       where
                          f state n = let (x',y',m') = (case (invaderX state,invaderY state , invaderM state ) of
                                                               (x,y,m) | x < 40 + (fst . invaderDims $ gameConfig )*(n-1) && m == R -> (x + 20,y, R)
                                                                       | m == R -> (x,y +20 , D)
                                                                       | m == D -> (x - 20, y,L)
                                                                       | m == L -> (x-20,y, D2)
                                                                       | otherwise -> (x,y +20,R) ) in  InvaderState {invaderX = x', invaderY = y' , invaderM = m'}


shipSignal :: Signal GameState -> Signal ShipState
shipSignal gameSignal = foldp modifyState initialState controlSignal
  where 
    initialState = 
      let (w,h)   = windowDims gameConfig
          (sw,sh) = shipDims   gameConfig
      in ShipState {shipX = w `div` 2 - sw `div` 2 - 10, 
                    shipY = h - sh}
    
    controlSignal :: Signal ((Int,Int),GameState)
    controlSignal = lift2 (,) Keyboard.arrows gameSignal

    modifyState :: ((Int,Int),GameState) -> ShipState -> ShipState
    modifyState ((dx,dy),gameState) state = 
      if status gameState == InProcess
      then state {shipX = shipX', shipY = shipY'}
      else state
        where shipX' = shipX state + 20 * dx --TODO: Мб стоит вынести константу в конфигурацию
              shipY' = shipY state

rocketSignal :: Signal GameState -> Signal ShipState -> Signal RocketState
rocketSignal gameSignal shipSignal = foldp modifyState initialState controlSignal
  where 
    initialState = RocketState {rocketX = -20, 
                                rocketY = (fromIntegral . snd . windowDims $ gameConfig) - 25, 
                                rocketFlying = False}
    
    controlSignal :: Signal (Bool, Double, GameState, ShipState)
    controlSignal = lift4 (,,,) (Keyboard.isDown Keyboard.SpaceKey) 
                                (Time.every $ 50 * Time.millisecond) -- тут скорость ракеты
                                gameSignal
                                shipSignal

    modifyState :: (Bool, Double, GameState, ShipState) -> RocketState -> RocketState
    modifyState (launched,time,gameState, shipState) state =
      if status gameState == InProcess 
      then state {rocketX = rocketX', rocketY = rocketY', rocketFlying = rocketFlying'}
      else initialState
      where
        rocketX' = if   rocketFlying' 
                   then rocketX state 
                   else shipX shipState + 35
        rocketY' = if   rocketFlying' 
                   then rocketY state - 10 -- Равномерненько
                   else rocketY initialState
        rocketFlying' = launched || 
                        (rocketY state > 0 && 
                          rocketY state < (snd . windowDims $ gameConfig) - 60)


renderDebugString :: String -> Form
renderDebugString = move (400, 100) . toForm . Text.plainText

startupMessage :: Form 
startupMessage = move (400, 300) . toForm . Text.text . formatText $ message
  where 
    formatText = (Text.color $ color) . Text.bold . Text.header . Text.toText
    message = "Press Space to play"
    color =  Color.rgba (50.0 / 255) (50.0 / 255) (50.0 / 255) (0.7)

invaderForm :: Int -> InvaderState -> Form
invaderForm color state = case color of 
                              0 -> move (fromIntegral $ invaderX state , fromIntegral $ invaderY state) $ toForm (invaderImg "Graphics/invaders/red_invader.png" gameConfig)
                              1 -> move (fromIntegral $ invaderX state , fromIntegral $ invaderY state) $ toForm (invaderImg "Graphics/invaders/black_invader.png" gameConfig)
                              2 -> move (fromIntegral $ invaderX state , fromIntegral $ invaderY state) $ toForm (invaderImg "Graphics/invaders/green_invader.png" gameConfig)

shipForm :: ShipState -> Form
shipForm state = move (fromIntegral $ shipX state,
                       fromIntegral $ shipY state) $ toForm (spaceShipImg gameConfig)

rocketForm :: RocketState -> Form
rocketForm state =
  move (fromIntegral $ rocketX state,
        fromIntegral $ rocketY state) $ filled rocketColor $ rect 10 10
  where
    rocketColor = Color.rgba (0.0 / 255) (0.0 / 255) (0.0 / 255) (0.7)

render :: (Int, Int) -> GameState -> [InvaderState]->[InvaderState] -> [InvaderState] -> ShipState ->RocketState -> Element
render (w, h) gameState redInvaderState blackInvaderState greenInvaderState shipState rocketState=
  let gameStatus = status gameState in 
  case gameStatus of 
   Startup -> collage w h $ 
      [toForm (backgroundImg gameConfig),startupMessage,shipForm shipState] ++ (map (invaderForm 0) redInvaderState )++
			 (map (invaderForm 1) blackInvaderState ) ++ ( map (invaderForm 2) greenInvaderState )  
                                                               
   InProcess -> case (any (\x -> invaderY x >= (snd . windowDims $ gameConfig) - (snd . shipDims $ gameConfig)) $ redInvaderState ++ blackInvaderState++greenInvaderState) of
                   True -> collage w h $ [toForm (backgroundImg gameConfig),renderDebugString "Over"]
                   _-> collage w h $ [toForm (backgroundImg gameConfig),renderDebugString "InProcess", shipForm shipState,rocketForm rocketState] ++ 
                           (map (invaderForm 0) redInvaderState) ++ (map (invaderForm 1) blackInvaderState )++ (map (invaderForm 2) greenInvaderState )


main :: IO ()
main = 
  let windowSignal = Window.dimensions
      shipSignal'   = shipSignal gameSignal
      redInvaderSignal' = invaderSignal 0 gameSignal 
      blackInvaderSignal' = invaderSignal 1 gameSignal
      greenInvaderSignal' = invaderSignal 2 gameSignal
      rocketSignal' = rocketSignal gameSignal shipSignal' 
  in  run (engineConfig gameConfig) $ render <~ 
        windowSignal ~~ gameSignal ~~ redInvaderSignal' ~~ blackInvaderSignal' ~~greenInvaderSignal' ~~ shipSignal'~~ rocketSignal'



