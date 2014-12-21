module Main where

import Data.Ord 

import FRP.Helm
import qualified FRP.Helm.Graphics  as Graphics
import qualified FRP.Helm.Keyboard  as Keyboard
import qualified FRP.Helm.Window    as Window
import qualified FRP.Helm.Text      as Text
import qualified FRP.Helm.Color     as Color
import qualified FRP.Helm.Time      as Time

-- Disclaimer: в рабочей версии комментариев возможны 
-- орфографические, синтаксические, пунктуационные, семантические
-- и другие ошибки. 

--------------------------------------------------------
-------------Types for game enteties states-------------
--------------------------------------------------------

-- Конфигурационная информация, будет представлена константным сигналом
data GameConfig = GameConfig {
  windowDims :: (Int,Int),
  shipDims   :: (Int,Int),
  rocketDims :: (Int,Int)}

-- Статус игры: ещё не начата, в процессе, окончена
data GameStatus = Startup | InProcess | Over
  deriving (Enum, Bounded,Eq)

data GameState = GameState {status :: GameStatus}

-- Тип, описывающий состояние фона окна, меняется вслед за стуатусом игры
--    До старта игры выводится приграшение к старту
--    В процессе игры выводится количество очков и здоровье кораблика
--    При проигрыше выводится соответсвующее сообщение

-- Тип, описывающий состояние кораблика: 
--    shipX, shipY - Координаты кораблика
--    rocketX, rocketY - Координаты выпущенной корабликом ракеты
--    rocketFlying - Выпущена ли ракета
--      На данный момент поддерживается только одина ракета, 
--      надо придумать, как сделать много
data ShipState = ShipState {shipX :: Int, shipY :: Int, shipHP :: Int} 

data RocketState = RocketState {
  rocketX :: Int, rocketY :: Int, rocketFlying :: Bool}

--------------------------------------------------------
--------------Initialisation of resources---------------
--------------------------------------------------------

-- Главный конфиг игры, управляет почти всеми параметрами
gameConfig :: GameConfig
gameConfig = GameConfig {
      windowDims = (450,800),
      shipDims   = (70,100),
      rocketDims = (10,10)
  }

-- Конфигурационная информация для библиотеки: размеры окна, заголовок окна, что-то там ещё
engineConfig :: GameConfig -> EngineConfig
engineConfig gameConfig = 
  EngineConfig (windowDims gameConfig) False False "Monad Invaders v0.0.1"

backgroundImg :: GameConfig -> Element
backgroundImg gameConfig = Graphics.fittedImage 
                (fst . windowDims $ gameConfig)
                (snd . windowDims $ gameConfig) "Graphics/3310screen.png"

spaceShipImg :: GameConfig -> Element
spaceShipImg gameConfig = Graphics.fittedImage 
                (fst . shipDims $ gameConfig) 
                (snd . shipDims $ gameConfig) "Graphics/3310ship.png"

--redInvaderImg :: Element
--redInvaderImg = Graphics.fittedImage 100 100 "img/red_invader.png"

--------------------------------------------------------
-----------------------Game logic-----------------------
--------------------------------------------------------

-- Главный сигнал игры. Описывает изменения состояния игры (GameState).
{-- 
  На данный момент работает так:
    В начале поле структуры status структуры GameState 
    имеет значение Startup (элемент перечисления GameStatus) -- 
    на экране изображено приглашение к началу игры.
    После первого нажатия на пробел поле status ппринимает значение 
    InProcess, то есть игра переходит в активное состояние, на экране
    виден кораблик, можно двигать его стрелочками.

  TODO: Реализовать переход в состояние Over, для этого надо расширить 
        состояние кораблика и его сигнал, а в сигнале игры обработать 
        "смерть" кораблика
--}
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

-- Сигнал кораблика, описывает поведение кораблика во времени
shipSignal :: Signal GameState -> Signal ShipState
shipSignal gameSignal = foldp modifyState initialState controlSignal
  where 
    initialState = 
      let (w,h)   = windowDims gameConfig
          (sw,sh) = shipDims   gameConfig
      in ShipState {shipX = w `div` 2 - sw `div` 2, 
                    shipY = h - sh, shipHP = 100}
    
    controlSignal :: Signal ((Int,Int),GameState)
    controlSignal = lift2 (,) Keyboard.arrows gameSignal

    modifyState :: ((Int,Int),GameState) -> ShipState -> ShipState
    modifyState ((dx,dy),gameState) state = 
      if status gameState == InProcess
      then state {shipX = shipX', shipY = shipY'}
      else state
        where shipX' = shipX state + 20 * dx
              shipY' = shipY state

-- Сигнал ракеты, зависит от сигнала кораблика.
--   Можно стрелять, нажмая на пробел, движение управляется таймером. 
--   TODO: БАГ!! Скорость движения ракеты зависит от нажатия на стрелочки 
--         (управление карабликом) -- пока не придумал, как с этим бороться
--         Дело в том, что сигнал кораблика является частью управляющего сигнала ракеты
--         но что с этим делать -- не понятно.
--         
--         Ещё БАГ!!! Первый выстрел происходит по нажатию на пробел, 
--         который относится к старту игры, а не к выстрелам
--   В этой функции  есть хардкод: он отражает положение ракеты относительно кораблика и 
--   количество пикселей, на которые смещается ракета при полёте
rocketSignal :: Signal GameState -> Signal ShipState -> Signal RocketState
rocketSignal gameSignal shipSignal = foldp modifyState initialState controlSignal
  where 
    initialState = RocketState {
      rocketX = -100,
      rocketY = (fromIntegral . snd . windowDims $ gameConfig) - 25, 
      rocketFlying = False}
        where
          w  = fst . windowDims $ gameConfig
          sw = fst . shipDims   $ gameConfig 
    
    controlSignal :: Signal (Bool, Time, GameState, ShipState)
    controlSignal = lift4 (,,,) (Keyboard.isDown Keyboard.SpaceKey) 
                                (Time.every $ 25 * Time.millisecond) -- тут скорость ракеты
                                gameSignal
                                shipSignal

    modifyState :: (Bool, Time, GameState, ShipState) -> RocketState -> RocketState
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

--------------------------------------------------------
-----------------------Rendering------------------------
--------------------------------------------------------

-- TODO: ИСКОРЕНИТЬ ХАРДКОД!!1!11

renderDebugString :: String -> Form
renderDebugString = move (400, 100) . toForm . Text.plainText

startupMessage :: Form 
startupMessage = move (posX, posY) . toForm . Text.text . formatText $ message
  where
    posX = 200
    posY = 100
    formatText = (Text.color $ color) . Text.bold . (Text.height 25) . Text.toText
    message = "Press Space to play"
    color =  Color.rgba (50.0 / 255) (50.0 / 255) (50.0 / 255) (0.7)

-- Рендеринг форм на основе элементов (изображений в формате png) и состояний объектов 

-- Фон
-- TODO: Можно добавить что-нибудь на фон (Хп кораблика, очки и т.п.)

-- Кораблик
shipForm :: ShipState -> Form
shipForm state = move (fromIntegral $ shipX state,
                       fromIntegral $ shipY state) $ toForm (spaceShipImg gameConfig)

-- Здоровье кораблика
shipHPForm :: ShipState -> Form 
shipHPForm state = 
  let (w,h) = windowDims gameConfig 
  in move (70, 
           fromIntegral $ h - 30) $ toForm . Text.text . formatText $ message
  where 
    formatText = (Text.color $ color) . Text.bold . Text.toText
    message = "Health: " ++ (show (shipHP state))
    color =  Color.rgba (50.0 / 255) (50.0 / 255) (50.0 / 255) (0.7)

-- Ракета кораблика
rocketForm :: RocketState -> Form
rocketForm state =
  move (fromIntegral $ rocketX state,
        fromIntegral $ rocketY state) $ filled rocketColor $ 
                                          rect (fromIntegral . fst . rocketDims $ gameConfig)
                                               (fromIntegral . snd . rocketDims $ gameConfig)
  where
    rocketColor = Color.rgba (0.0 / 255) (0.0 / 255) (0.0 / 255) (0.7)

-- Рендеринг общей сцены 
render :: (Int, Int) -> GameState -> ShipState -> RocketState -> Element
render (w, h) gameState shipState rocketState =
  let gameStatus = status gameState in 
  case gameStatus of 
    Startup -> collage w h $ 
      [toForm (backgroundImg gameConfig),startupMessage,shipForm shipState,
       rocketForm rocketState]
    InProcess -> collage w h $ 
      [toForm (backgroundImg gameConfig),renderDebugString "InProcess",
       rocketForm rocketState, shipForm shipState, shipHPForm shipState]
    Over -> collage w h $ 
      [toForm (backgroundImg gameConfig),renderDebugString "Over"]

main :: IO ()
main = 
  let windowSignal = Window.dimensions
      shipSignal'   = shipSignal gameSignal
      rocketSignal' = rocketSignal gameSignal shipSignal' 
  in  run (engineConfig gameConfig) $ render <~ 
        windowSignal ~~ gameSignal ~~ shipSignal' ~~ rocketSignal'

