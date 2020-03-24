{-
Collaborative New York Times Crossword application
David Brandman. March 2020

Here's how this works:

1) This talks to the Flask websocket server and requests a copy of the crossword
2) Display the crossword to the user
3) When a user makes a keyboard entry, it's parsed in the KeyDown Msg. 
4) Changes are made to the model, and then updates are sent via websocket
5) This model subscribes to ports that can update regarding grid and position entries from others

I'm happy with how a lot of this code turned out. There are a few design choices that may be questionable:

1) Setting sub-structures is super efficient. I thought about a
flattened model design but with my background in Matlab I find this hard
to maanage. Surely, there's a more efficient way than to have so many
setter functions. But I'm unaware.

2) I could have used an elm library for playing with websockets. I decided
I wanted to play with ports instead. But this'll be for a future version.

3) I created 3 different websocket namespaces for each of the different
types of packets. An equivalent way would be to just have a more complex
JSON struct. This may be more elegant, but having separate namespaces
makes things really clear.

4) I considered "Reveal" to be a keyboard entry.


-}
port module Crossword exposing (..)

import Html exposing (..) 
import Html.Attributes exposing ( attribute, style, src, placeholder, type_, href, rel, class, value , classList, id )
import Html.Events exposing (onClick, onInput, onCheck, onDoubleClick)

import Http

import List.Extra 
import String.Extra
import Browser
import Browser.Dom
import Browser.Events

import Json.Decode 
import Json.Encode
import Json.Decode.Pipeline exposing (required, optional, hardcoded) 

import Task
import Time
import Dict exposing (Dict)

serverURL : String
serverURL = "http://127.0.0.1:5000/"


main =
  Browser.element
    { init          = init
    , update        = update
    , subscriptions = subscriptions
    , view          = view
    }

{-

These ports send/receive websocket information. There are three different
types of information: Information about grid entries, about their
positions on the board, and this user's session ID number
-}


port toJS_GridUpdate : String -> Cmd msg
port toElm_GridUpdate : (String -> msg) -> Sub msg

port toJS_PositionUpdate : String -> Cmd msg
port toElm_PositionUpdate : (String -> msg) -> Sub msg

port toElm_ID : (String -> msg) -> Sub msg

run : Msg -> Cmd Msg
run m =
    Task.perform (always m) (Task.succeed ())

--------------------------------------------------
--------------------------------------------------
-- SUBSCRIPTIONS
--------------------------------------------------
--------------------------------------------------

{-
I am subscribed to the ports, and to a listener for the various keyboard inputs
-}

subscriptions : Model -> Sub Msg
subscriptions model =
    let
        keyDecoder : Json.Decode.Decoder String
        keyDecoder =
            Json.Decode.field "key" Json.Decode.string

    in
        Sub.batch
        [ Browser.Events.onKeyDown (Json.Decode.map KeyDown keyDecoder)
        , toElm_GridUpdate ParseWebsocketGridInfo 
        , toElm_PositionUpdate ParseWebsocketPositionInfo
        , toElm_ID ParseWebsocketID
        ]



--------------------------------------------------
--------------------------------------------------
-- MODEL
--------------------------------------------------
--------------------------------------------------

type alias GridSize = 
    { cols : Int 
    , rows : Int
    }

type alias Clues =
    { across : List String -- A list of the across clues
    , down  : List String  -- A lsit of the down clues
    }

type alias CrosswordModel =
    { gridSize     : GridSize
    , clues        : Clues
    , grid         : List String -- This contains the entries PRESENTED to the user
    , gridNumbers  : List Int
    , title        : String
    , answerGrid   : List String -- This contains the RIGHT ANSWERS
    , revealedGrid : List Int    -- This contains which squares have been "revealed"
    }

type KeyboardEntryType = KeyNothing | KeySpace | KeyDelete | KeyLetter | KeyArrow | KeyReveal

type alias StateInfo =
    { keyboardEntryType : KeyboardEntryType -- Has the user pushed an arrow key, entered a letter, etc.
    , gridUpdateStruct  : GridUpdateStruct  -- Contains info that will be sent out by websocket
    }

type alias ServerInfo =
    { serverURL             : String
    , crosswordDownloaded   : Bool
    , websocketID           : String -- Unique session ID provided by the server
    }

type HighlightedDirection = HighlightAcross | HighlightDown

type alias SquareSelectedInfo =
    { selected             : Int                  -- What square has the user actually selected
    , highlightedDirection : HighlightedDirection
    , highlightedClue      : Int                  -- Which clue number should be presented
    , highlightedGrid      : List Int             -- Which squares should be highlighted
    , otherUsersPositions  : List Int
    }

type alias ClueDisplayInfo =
    { acrossClueList   : Dict String String -- A Dictionary mapping clue numbers to the string content
    , downClueList     : Dict String String
    , wrongAnswerGrid  : List Int -- Which squares are wrong
    , showWrongAnswers : Bool -- Does the user want to show the wrong answers
    }
type alias Model = 
    { crossword          : CrosswordModel
    , stateInfo          : StateInfo
    , serverInfo         : ServerInfo
    , squareSelectedInfo : SquareSelectedInfo
    , clueDisplayInfo    : ClueDisplayInfo
    }


{- This is the websocket packet that updates what the user just entered or revealed -}
type alias GridUpdateStruct =
    { position : String
    , value    : String
    , method   : String
    }

{- This is the websocket packet that updates where the user just moved to -}
type alias PositionUpdateList =
    { websocketID : List String
    , position    : List String 
    }


--------------------------------------------------
--------------------------------------------------
-- INIT
--------------------------------------------------
--------------------------------------------------
{- Try to download the model. If it doesn't work, it'll prompt the user to select the port information -}

init : () -> (Model, Cmd Msg)
init _ = 
    (initialModel , downloadCrossword initialModel)

initialStateInfo : StateInfo
initialStateInfo =
    { keyboardEntryType = KeyNothing
    , gridUpdateStruct = {position = "" , value = "" , method = ""}
    }

initialServerInfo : ServerInfo
initialServerInfo =
    { 
      serverURL           = serverURL
    , crosswordDownloaded = False
    , websocketID         = ""
    }

initialSquareSelectedInfo : SquareSelectedInfo
initialSquareSelectedInfo =
    { selected = 0
    , highlightedDirection = HighlightAcross
    , highlightedClue      = 1
    , highlightedGrid      = []
    , otherUsersPositions  = []
    }


initialClueDisplayInfo : ClueDisplayInfo
initialClueDisplayInfo =
    { acrossClueList   = Dict.empty
    , downClueList     = Dict.empty
    , wrongAnswerGrid  = []
    , showWrongAnswers = False
    }

initialCrosswordModel : CrosswordModel
initialCrosswordModel =
    let
        emptyGridSize : GridSize
        emptyGridSize = 
            { cols = 0, rows = 0}

        emptyClues : Clues
        emptyClues = 
            {across = [], down = [] }

    in
        { gridSize     = emptyGridSize
        , clues        = emptyClues
        , grid         = []
        , gridNumbers  = []
        , title        = ""
        , answerGrid   = []
        , revealedGrid = []
        }

initialModel : Model
initialModel =
    {     crossword          = initialCrosswordModel
        , stateInfo          = initialStateInfo
        , serverInfo         = initialServerInfo
        , squareSelectedInfo = initialSquareSelectedInfo
        , clueDisplayInfo    = initialClueDisplayInfo
    }

--------------------------------------------------
--------------------------------------------------
-- UPDATE
--------------------------------------------------
--------------------------------------------------

{-
For logistical reasons I made the "Reveal" onClick command to be a keyboard command
The reasoning of this is that you can imagine having a button (F1?) that would
reveal what's happened. 

-}


type Msg 
    = DownloadCrossword                                   -- Send a request to the server to get something
    | ParseDownloadedCrossword (Result Http.Error String) -- Read the JSON and populate the model
    | KeyDown String                                      -- The user has pushed a keyboard button
    | RevealSquare                                        -- Reveal the current square
    | SetServerURL String                                 -- Set the URL to begin the connection
    | CheckAnswers                                        -- Toggle whether wrong answers are displayed
    | MouseClick Int                                      -- Use the mouse to move the selected entry
    | MouseDoubleClick Int                                -- Move selected entry and toggle direction
    | ParseWebsocketGridInfo String                       -- Manage websockets about grid
    | ParseWebsocketPositionInfo String                   -- Manage websockets about positions
    | ParseWebsocketID String                             -- Manage websockets about this ID

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =

    case msg of
        DownloadCrossword ->
            (model, downloadCrossword model)

        ParseDownloadedCrossword result ->
            (parseDownloadedCrossword result model, Cmd.none)

        KeyDown str ->
            ( updateKeyDown str model , websocketEmit model)

        RevealSquare ->
            ( updateKeyDown "Reveal" model, websocketEmit model)

        SetServerURL url ->
            (setServerURL url model, Cmd.none)

        CheckAnswers ->
            (checkAnswers model, Cmd.none)

        ParseWebsocketGridInfo str ->
            (parseWebsocketGridInfo str model, Cmd.none)

        ParseWebsocketPositionInfo str ->
            (parseWebsocketPositionInfo str model, Cmd.none)

        ParseWebsocketID str ->
            (parseWebsocketID str model, Cmd.none)

        MouseClick val ->
            (mouseClick val model,  websocketEmit model)

        MouseDoubleClick val ->
            (mouseDoubleClick val model, websocketEmit model)

--------------------------------------------------
--------------------------------------------------
-- Respond when a key is pressed
--------------------------------------------------
--------------------------------------------------

{- When the user uses the keyboard, interpret what type of command it was.
It can be an arrow, alpha, delete, etc. -}

parseKeyboardEntryType : String -> KeyboardEntryType
parseKeyboardEntryType key =
    let
        getFirstLetter : Char
        getFirstLetter =
            key
            |> String.toList
            |> List.head
            |> Maybe.withDefault '0'
    in
        if (Char.isAlpha getFirstLetter) && (Char.isLower getFirstLetter) then
            KeyLetter
        else if key == "Backspace" || key == "Delete" then
            KeyDelete
        else if key == " " then
            KeySpace
        else if key == "ArrowLeft" || key == "ArrowRight" || key == "ArrowDown" || key == "ArrowUp" then
            KeyArrow
        else if key == "Reveal" then
            KeyReveal
        else
            KeyNothing
        

doKeyArrow : String -> Model -> Model
doKeyArrow key model =
    let
        keyOffset : Int
        keyOffset =
            case key of
                "ArrowLeft"  -> -1
                "ArrowRight" ->  1
                "ArrowDown"  ->  model.crossword.gridSize.cols
                "ArrowUp"    -> -model.crossword.gridSize.cols
                _            -> 0

        nextInd : Int -> Int
        nextInd i =
           case (List.Extra.getAt i model.crossword.grid) of
               Just nextGridStr ->
                   case nextGridStr of
                       "." -> nextInd (i + keyOffset) -- Corresponds to a black square
                       _   -> i
               Nothing -> model.squareSelectedInfo.selected

        nextSquareSelectedValue = (nextInd (model.squareSelectedInfo.selected + keyOffset))
    in
        model
        |> setKeyboardEntryType KeyArrow
        |> setMySquareSelectedValue nextSquareSelectedValue -- Move the selected square
        |> setNextClueToDisplay                             -- Set the next clue to display based on the new selected square
        |> setNextHighlightedGrid                           -- Set what squares to highlight based on the new selected square
        |> setGridUpdateStruct 

doKeyDelete : String -> Model -> Model
doKeyDelete key model =
    model
    |> setKeyboardEntryType KeyDelete
    |> setGridAtInd model.squareSelectedInfo.selected " " -- Set the selected square to be empty
    |> setGridUpdateStruct 

doKeyLetter : String -> Model -> Model
doKeyLetter key model =
    let
        indOffset : Int
        indOffset =
            case model.squareSelectedInfo.highlightedDirection of
                HighlightAcross -> 1
                HighlightDown   -> model.crossword.gridSize.cols

        nextInd : Int -> Int
        nextInd i =
           case (List.Extra.getAt i model.crossword.grid) of
               Just nextGridStr ->
                   case nextGridStr of
                       "." -> nextInd (i + indOffset)
                       _   -> i
               Nothing -> model.squareSelectedInfo.selected

        nextSquareSelectedValue = (nextInd (model.squareSelectedInfo.selected + indOffset))
    in
        model
        |> setKeyboardEntryType KeyLetter
        |> setGridAtInd model.squareSelectedInfo.selected (String.toUpper key) -- Set the selected square to be the letter
        |> setGridUpdateStruct                                                 -- Set the websocket packet to be sent out
        |> setMySquareSelectedValue nextSquareSelectedValue                    -- Move the selected square down or right
        |> setNextClueToDisplay                                                -- See the next clue
        |> setNextHighlightedGrid                                              -- Change what is highlighted

doKeySpace : String -> Model -> Model
doKeySpace key model =
    model
    |> setKeyboardEntryType KeySpace
    |> toggleHighlightedDirection -- Change if you're highlighting across or down
    |> setNextClueToDisplay -- See the next clue
    |> setNextHighlightedGrid -- See which squares should be highlighted

doKeyNothing : String -> Model -> Model
doKeyNothing key model =
    model
    |> setKeyboardEntryType KeyNothing

doKeyReveal : String -> Model -> Model
doKeyReveal key model =
    model
    |> setKeyboardEntryType KeyReveal
    |> appendToRevealedGrid model.squareSelectedInfo.selected -- Add this location to the list of squares revealed
    |> revealSquare model.squareSelectedInfo.selected -- Copy from answerGrid to grid
    |> setGridUpdateStruct 

updateKeyDown : String -> Model ->Model
updateKeyDown key model =
    case (parseKeyboardEntryType key) of
        KeyLetter  -> doKeyLetter  key model
        KeyDelete  -> doKeyDelete  key model
        KeySpace   -> doKeySpace   key model
        KeyArrow   -> doKeyArrow   key model
        KeyReveal  -> doKeyReveal  key model
        KeyNothing -> doKeyNothing key model


{-
This took some time to figure out. Recursive function. 
1) Look at my current position. Decide if I want to start looking up or left. Let's say left.
2) Now loook left. Are you at the edge of the board? Are you a black square? If so, then stop. If not, go back to (1)
3) If you've stopped, then set the clue based on where you've ended up
-}

setNextClueToDisplay : Model -> Model
setNextClueToDisplay model =
    let
        nextOffset : Int
        nextOffset =
            case model.squareSelectedInfo.highlightedDirection of
                HighlightAcross -> -1
                HighlightDown   -> -model.crossword.gridSize.cols

        clueNumber : Int -> Int
        clueNumber n =
            if Maybe.withDefault " " (List.Extra.getAt (n + nextOffset) model.crossword.grid) == "." then
                n
            else if (modBy 15 n ) == 0 && (model.squareSelectedInfo.highlightedDirection == HighlightAcross) then
                n
            else if (n + nextOffset) < 0 then
                n
            else
                clueNumber (n + nextOffset)
    in
        model
        |> setHighlightedClue (clueNumber model.squareSelectedInfo.selected)

{- Some people like using mice. I'm not one of them. Jump to where the user has clicked on the screen -}

mouseClick : Int -> Model -> Model
mouseClick toFocus model =
    model
    |> setKeyboardEntryType KeyArrow
    |> setMySquareSelectedValue toFocus -- toFocus contains the grid number
    |> setNextClueToDisplay -- Update which clue to display
    |> setNextHighlightedGrid  -- Change which grid entries are highlighted
    |> setGridUpdateStruct 

mouseDoubleClick : Int -> Model -> Model
mouseDoubleClick toFocus model =
    model
    |> setKeyboardEntryType KeyArrow
    |> setMySquareSelectedValue toFocus -- toFocus contains the grid number
    |> toggleHighlightedDirection -- Change if you're highlighting across or down
    |> setNextClueToDisplay -- See the next clue
    |> setNextHighlightedGrid -- See which squares should be highlighted
    |> setGridUpdateStruct 

--------------------------------------------------
--------------------------------------------------
-- SERVER COMMUNICATION
--------------------------------------------------
--------------------------------------------------

downloadCrossword : Model -> Cmd Msg
downloadCrossword model =
    Http.get 
    { url = model.serverInfo.serverURL ++ "crossword"
    , expect = Http.expectString ParseDownloadedCrossword
    }

parseDownloadedCrossword : (Result Http.Error String) -> Model -> Model
parseDownloadedCrossword result model =
    case result of
        Ok jsonText -> 
            case Json.Decode.decodeString decodeCrosswordJsonToModel jsonText of
                Ok crosswordModel -> 
                    {model | crossword = crosswordModel } 
                    |> setCrosswordDownloaded True
                    |> setClueDisplayInfo
                    |> copyFromRevealedToGrid 
                    |> setNextClueToDisplay 
                    |> setNextHighlightedGrid 
                            
                Err e -> 
                    model
                        |> Debug.log ("ERROR: " ++ (Json.Decode.errorToString e))

        Err errorType -> 
            model
                |> Debug.log ( "ERROR DEALING WITH RESULT OF JSON: " ++ (httpErrorType errorType))


{- If the user has moved, entered a letter, deleted a letter, or revealed a letter, we need to update the server.
We start by looking into the model, generating a JSON formatted string, and then sending it.
We send it using a port, since I didn't implement the code using an Elm websocket library. For the next version!-}

websocketEmit : Model -> Cmd Msg
websocketEmit model =

    let
        gridJsonString = 
            [ ("position", Json.Encode.string model.stateInfo.gridUpdateStruct.position)
            , ("value"   , Json.Encode.string model.stateInfo.gridUpdateStruct.value)
            , ("method"  , Json.Encode.string model.stateInfo.gridUpdateStruct.method)
            ] 
            |> Json.Encode.object
            |> Json.Encode.encode 0
            |> Debug.log ("SENDING")

        positionJsonString =
            [ ("position" , Json.Encode.string model.stateInfo.gridUpdateStruct.position)
            ]
            |> Json.Encode.object
            |> Json.Encode.encode 0

    in
        if List.member model.stateInfo.keyboardEntryType [KeyLetter, KeyDelete, KeyReveal] then
            toJS_GridUpdate gridJsonString
        else if model.stateInfo.keyboardEntryType == KeyArrow then
            toJS_PositionUpdate positionJsonString
        else
            Cmd.none


parseWebsocketGridInfo : String -> Model -> Model
parseWebsocketGridInfo jsonText model =
    let
        buildGridUpdateStruct : Json.Decode.Decoder GridUpdateStruct
        buildGridUpdateStruct =
            Json.Decode.succeed GridUpdateStruct
                |> required "position" Json.Decode.string
                |> required "value" Json.Decode.string
                |> required "method" Json.Decode.string

        toInt : String -> Int
        toInt pos =
            (Maybe.withDefault 0 (String.toInt pos))

    in
        case Json.Decode.decodeString buildGridUpdateStruct jsonText of
            Ok wsStruct ->
                if wsStruct.method == "revealed" then
                    model
                    |> appendToRevealedGrid (toInt wsStruct.position)
                    |> revealSquare (toInt wsStruct.position)
                else
                   setGridAtInd (toInt wsStruct.position) wsStruct.value model
            Err e ->
                Debug.log ("ERROR ParseWebsocketGridInfo: " ++ (Json.Decode.errorToString e)) model

parseWebsocketPositionInfo : String -> Model -> Model
parseWebsocketPositionInfo jsonText model =
    let

        buildPositionUpdateStruct : Json.Decode.Decoder PositionUpdateList
        buildPositionUpdateStruct =
            Json.Decode.succeed PositionUpdateList
                |> required "websocketID" (Json.Decode.list Json.Decode.string)
                |> required "position" (Json.Decode.list Json.Decode.string)

        toInt : String -> Int
        toInt pos =
            (Maybe.withDefault 0 (String.toInt pos))

    in
        case Json.Decode.decodeString buildPositionUpdateStruct (Debug.log "JSON" jsonText ) of
            Ok wsStruct ->
                model
                |> setOtherUsersPositions (List.map toInt wsStruct.position)
                |> removeSelfFromUserPositions wsStruct.websocketID
            Err e ->
                Debug.log ("ERROR BuildGridUpdateStruct: " ++ (Json.Decode.errorToString e)) model

removeSelfFromUserPositions : List String -> Model -> Model
removeSelfFromUserPositions idList model =
    let
        myPosition : Maybe Int
        myPosition = List.Extra.findIndex (\n -> n == model.serverInfo.websocketID) idList

        newOtherPositionList = 
            case myPosition of
                Just indToRemove -> List.Extra.removeAt indToRemove model.squareSelectedInfo.otherUsersPositions
                Nothing -> model.squareSelectedInfo.otherUsersPositions

        squareSelectedInfo = model.squareSelectedInfo
        newSquareSelectedInfo = {squareSelectedInfo | otherUsersPositions = newOtherPositionList}
    in
        {model | squareSelectedInfo = newSquareSelectedInfo}

setOtherUsersPositions : List Int -> Model -> Model
setOtherUsersPositions posList model =
    let
        squareSelectedInfo = model.squareSelectedInfo
        newSquareSelectedInfo = {squareSelectedInfo | otherUsersPositions = posList}

    in
        {model | squareSelectedInfo = newSquareSelectedInfo}

parseWebsocketID : String -> Model -> Model
parseWebsocketID idString model =
    setWebsocketID idString model

--------------------------------------------------
--------------------------------------------------
-- CHECKING AND REVEALING
--------------------------------------------------
--------------------------------------------------

{-
To find the wrong answers, use map2 to compare the user's grid and the answers.
Next, use elemIndices True to find which of those indexes are true. This is a holdover
from my Matlab days when you'd use find() function to get the indices of your matches
-}

checkAnswers : Model -> Model
checkAnswers masterModel =
    let
        findWrongAnswers : Model -> Model
        findWrongAnswers model =
            let
                wrongAnswers = 
                    List.map2 (\a b -> a /= b) model.crossword.grid model.crossword.answerGrid
                    |> List.Extra.elemIndices True

                clueDisplayInfo    = model.clueDisplayInfo
                newClueDisplayInfo = {clueDisplayInfo | wrongAnswerGrid = wrongAnswers}
            in
                {model | clueDisplayInfo = newClueDisplayInfo}
    in
        if masterModel.clueDisplayInfo.showWrongAnswers then
            masterModel 
            |> setShowWrongAnswers False
        else
            masterModel 
            |> findWrongAnswers
            |> setShowWrongAnswers True

appendToRevealedGrid : Int -> Model -> Model
appendToRevealedGrid val model =
    let
        crossword = model.crossword
        newCrossword = {crossword | revealedGrid = val :: model.crossword.revealedGrid}
    in
        {model | crossword = newCrossword}

revealSquare : Int -> Model -> Model
revealSquare indToReveal model =
    let
        revealedLetter : String
        revealedLetter = 
            case List.Extra.getAt indToReveal model.crossword.answerGrid of
                Just correctChar -> correctChar
                Nothing -> "0"
    in
        model 
        |> setGridAtInd indToReveal revealedLetter

copyFromRevealedToGrid : Model -> Model
copyFromRevealedToGrid model =
    List.foldr revealSquare model (model.crossword.revealedGrid)


--------------------------------------------------
--------------------------------------------------
-- VIEW
--------------------------------------------------
--------------------------------------------------

{-
There are two display modes: A connection has been made, or a connection has not been made.
In the former, we show the crossword and clues. In the latter, we show a screen that allows
the user to set the server information
-}

view : Model -> Html Msg
view model =
    let
        displayConnectionScreen : Html Msg
        displayConnectionScreen =
            displayInitialization model

        displayCrosswordScreen : Html Msg
        displayCrosswordScreen =
            div [class "container"] 
            [ div [class "row"]
              [ div [class "column column-50"] [ displayHeader model ]
              , div [class "column column-50"] [ displayAnswerButtons model ]
            ]
            , div [class "row"] 
              [ div [class "column column-50"] 
                [ div [class "isFixed"] 
                  [ displayCrossword model 
                  , displaySingleClue model]
                ] 
              , div [class "column column-50"] [ displayClues model ]
              ]
            ]

        displayContents : Html Msg
        displayContents = 
            if model.serverInfo.crosswordDownloaded then
                displayCrosswordScreen
            else
                displayConnectionScreen
    in
        main_ [] 
        [  displayContents
        ]


{-
1) Define what a single TD entry looks like. Format it based on whether it's revealed, the answer is being displayed, it's currently selected, etc.
2) Build up a row of these. 
3) Combine all of the rows and then jam it into the table contents
-}


displayCrossword : Model -> Html Msg
displayCrossword model = 
    let
        isSelected : Int -> Bool
        isSelected n = 
            model.squareSelectedInfo.selected == n 

        isWrong : Int -> Bool
        isWrong n =
            model.clueDisplayInfo.showWrongAnswers && (List.member n model.clueDisplayInfo.wrongAnswerGrid)

        isHighlighted : Int -> Bool
        isHighlighted n =
            List.member n model.squareSelectedInfo.highlightedGrid

        isRevealed : Int -> Bool
        isRevealed n =
            List.member n model.crossword.revealedGrid

        isOtherUsers : Int -> Bool
        isOtherUsers n =
            List.member n model.squareSelectedInfo.otherUsersPositions -- && n /= model.squareSelectedInfo.lastPosition

        tdClass : Int -> String
        tdClass ind =
            let
                descriptor : String
                descriptor =
                    if isSelected ind then
                        "gridSelected"
                    else if isHighlighted ind then
                        "gridHighlighted"
                    else if isRevealed ind then
                        "gridRevealed"
                    else if isWrong ind then
                        "gridWrong"
                    else if isOtherUsers ind then
                        "gridOtherUserPosition"
                    else
                        ""
            in
                "gridEntry" ++ " " ++ descriptor


        gridEntryValue : Int -> String
        gridEntryValue ind =
            case (List.Extra.getAt ind model.crossword.grid) of
                Just val -> if val == " " then "" else val
                Nothing  -> ""

        gridNumber : Int -> String
        gridNumber ind =
            case (List.Extra.getAt ind model.crossword.gridNumbers) of
                Just val -> if val == 0 then "" else (String.fromInt val)
                Nothing -> ""

        -- This function either shows a black square or shows the letter with the proper formatting 
        gridEntry : Int -> String -> Html Msg
        gridEntry ind char =
            case char of
                "." ->
                    td [class "gridEntry gridEmpty"] [] 
                _ ->
                    td [class (tdClass ind)] 
                    [ div [id "crosswordNumber", onClick (MouseClick ind), onDoubleClick (MouseDoubleClick ind)] 
                      [text (gridNumber ind)]
                    , div [ class "crosswordInput", onClick (MouseClick ind), onDoubleClick (MouseDoubleClick ind)]
                      [text (gridEntryValue ind)]
                    ]

        numCols : Int
        numCols = model.crossword.gridSize.cols

        {-
        0) Base case: There are no more grid entries to display
        1) Map2 the gridEntry function with (which grid number to start) and (the grid of letters)
        2) Wrap this in a tr
        3) Append this to the rows created already
        4) Call function again, and move the starting points, and drop entries from list of grid
        -}

        crosswordRow : Int -> List String -> List (Html Msg) -> List (Html Msg)
        crosswordRow nEntries grid gridRow =
          
          if List.isEmpty grid then -- Basecase
             gridRow
          else 
            List.map2 gridEntry 
                (List.range nEntries (nEntries+numCols))
                (List.take numCols grid) 
            |> tr [] 
            |> List.singleton
            |> List.append gridRow
            |> crosswordRow (nEntries+numCols) (List.drop numCols grid)

    in 
        table [class "crosswordGridTable"] (crosswordRow 0 model.crossword.grid [] )


displayClues : Model -> Html Msg
displayClues model =
    table [class ""]
    [ thead [] 
      [ tr [] 
        [ th [] [text "Across"] 
        , th [] [text "Down"] 
        ]
      ]
    , tbody []  
      [ tr []
        [ td [class "clueColumn"] 
          [ table [] 
            (List.map (\x -> tr [] [td [] [text (removeEscapeCharacters x)]]) model.crossword.clues.across )
          ]
        , td [class "clueColumn"] 
          [table [] 
            ( List.map (\x -> tr [] [td [] [text (removeEscapeCharacters x)]]) model.crossword.clues.down ) ]
        ]
      ]
    ]

{- This is the clue displayed immediately below crossword -}

displaySingleClue : Model -> Html Msg
displaySingleClue model =
    let
        toDisplay : String
        toDisplay = ""

        currentSquare : String
        currentSquare = 
            case List.Extra.getAt (model.squareSelectedInfo.highlightedClue) model.crossword.gridNumbers of
                Just n -> (String.fromInt n)
                Nothing -> (String.fromInt -100)

        show : String
        show =
            case model.squareSelectedInfo.highlightedDirection of
                HighlightAcross -> Maybe.withDefault "" (Dict.get currentSquare model.clueDisplayInfo.acrossClueList)
                HighlightDown   -> Maybe.withDefault "" (Dict.get currentSquare model.clueDisplayInfo.downClueList)
    in
        div [] 
        [ h3 [] [text (currentSquare ++ ": " ++ removeEscapeCharacters show)]
        ]

    
{- This are the buttons that reveal squares -}

displayAnswerButtons : Model -> Html Msg
displayAnswerButtons model =
    let
        checkClass : String
        checkClass = if model.clueDisplayInfo.showWrongAnswers then "button button-outline" else "button"

        checkText : String
        checkText = if model.clueDisplayInfo.showWrongAnswers then "Hide wrong squares" else "Show wrong squares"

    in
        table [] 
        [ tr [] 
          [ td [] [ button [class checkClass, onClick CheckAnswers] [text checkText] ]
          , td [] [ button [class "button", onClick RevealSquare] [text "Reveal square"] ]
          ]
        ]

displayHeader : Model -> Html Msg
displayHeader model =
    h2 [] [text model.crossword.title]

{- If we haven't been able to load the model, prompt the user for server information -}

displayInitialization : Model -> Html Msg
displayInitialization model =
    div [class "wholeScreen"] 
    [ div [class "initialization"]
      [ h1 [] [text "Remote Server URL"]
      , input [attribute "type" "text", value model.serverInfo.serverURL, onInput SetServerURL] []
      , button [class "button", onClick DownloadCrossword] [text "Connect"]
      ]
    ]


--------------------------------------------------
--------------------------------------------------
-- HELPERS
--------------------------------------------------
--------------------------------------------------

numBoxes : Model -> Int
numBoxes model =
     model.crossword.gridSize.cols * model.crossword.gridSize.rows

setWebsocketID : String -> Model -> Model
setWebsocketID val model =
    let
        serverInfo = model.serverInfo
        newServerInfo = {serverInfo | websocketID = Debug.log "MYID:" val}
    in
        {model | serverInfo = newServerInfo }

setCrosswordDownloaded : Bool -> Model -> Model
setCrosswordDownloaded val model =
    let
        serverInfo = model.serverInfo
        newServerInfo = {serverInfo | crosswordDownloaded = val}
    in
        {model | serverInfo = newServerInfo }

setMySquareSelectedValue : Int -> Model -> Model
setMySquareSelectedValue val model =
    let
       squareSelectedInfo = model.squareSelectedInfo
       newSquareSelectedInfo = {squareSelectedInfo | selected = val} 
    in
        {model | squareSelectedInfo = newSquareSelectedInfo}

setClueDisplayInfo : Model -> Model
setClueDisplayInfo model =
    let
        buildDict : List String -> Dict String String
        buildDict clueList =
            let
                keys = List.map (String.Extra.leftOf ".")  clueList 
                vals = List.map (String.Extra.rightOf ".") clueList
            in
                List.Extra.zip keys vals
                |> Dict.fromList

        newClueDisplayInfo = {acrossClueList = buildDict model.crossword.clues.across,
                              downClueList   = buildDict model.crossword.clues.down,
                              wrongAnswerGrid = [],
                              showWrongAnswers = False
                             }
    in
        {model | clueDisplayInfo = newClueDisplayInfo}

setGridAtInd : Int -> String -> Model -> Model
setGridAtInd ind char model =
    let
        newGrid = List.Extra.setAt ind (String.toUpper char) model.crossword.grid
        oldCrossword = model.crossword
        newCrossword = {oldCrossword | grid = newGrid}
    in
        {model | crossword = newCrossword}



setShowWrongAnswers : Bool -> Model -> Model
setShowWrongAnswers val model = 
    let
        clueDisplayInfo = model.clueDisplayInfo
        newClueDisplayInfo = {clueDisplayInfo | showWrongAnswers = val }
    in
        {model | clueDisplayInfo = newClueDisplayInfo}

setServerURL : String -> Model -> Model
setServerURL url model =
    let
        serverInfo = model.serverInfo
        newServerInfo = {serverInfo | serverURL = url}
    in
        {model | serverInfo = newServerInfo}

toggleHighlightedDirection : Model -> Model
toggleHighlightedDirection model =
    let
        newDirection : HighlightedDirection
        newDirection =
            case model.squareSelectedInfo.highlightedDirection of
                HighlightAcross -> HighlightDown
                HighlightDown    -> HighlightAcross

        squareSelectedInfo = model.squareSelectedInfo
        newSquareSelectedInfo = {squareSelectedInfo | highlightedDirection = newDirection}
    in
        {model | squareSelectedInfo = newSquareSelectedInfo}

removeEscapeCharacters : String -> String
removeEscapeCharacters str =
    str
    |> String.replace "&quot;" "\""
    |> String.replace "&#39;" "'"
    |> String.replace "&amp;" "&"

httpErrorType errorType =
    case errorType of
        Http.BadUrl str ->
            "Bad URL error: " ++ str
        Http.Timeout ->
            "Network timeout error"
        Http.NetworkError ->
            "Unspecified Network error"
        Http.BadStatus val ->
            "Bad status error: " ++ (String.fromInt val)
        Http.BadBody str ->
            "Bad body error: " ++ str

setNextHighlightedGrid : Model -> Model
setNextHighlightedGrid model =
    let
        nextOffset : Int
        nextOffset =
            case model.squareSelectedInfo.highlightedDirection of
                HighlightAcross -> 1
                HighlightDown   -> model.crossword.gridSize.cols

        getSquares : List Int -> List Int
        getSquares theList =
            case List.head theList of
                Just firstN ->
                    if Maybe.withDefault " " (List.Extra.getAt (firstN + nextOffset) model.crossword.grid) == "." then
                        theList
                    else if (modBy 15 (firstN + nextOffset)) == 0 && (nextOffset == 1) then
                        theList
                    else if (firstN + nextOffset) > (numBoxes model) then
                        theList
                    else
                        getSquares ((firstN + nextOffset) :: theList)

                Nothing -> theList

        newHighlightedGrid = 
            (  getSquares (List.singleton model.squareSelectedInfo.highlightedClue))
        squareSelectedInfo = model.squareSelectedInfo
        newSquareSelectedInfo = {squareSelectedInfo | highlightedGrid = newHighlightedGrid}

    in
        {model | squareSelectedInfo = newSquareSelectedInfo}

setHighlightedClue : Int -> Model -> Model
setHighlightedClue ind model =
    let
        squareSelectedInfo = model.squareSelectedInfo
        newSquareSelectedInfo = {squareSelectedInfo | highlightedClue = ind}
    in
        {model | squareSelectedInfo = newSquareSelectedInfo}

setKeyboardEntryType : KeyboardEntryType -> Model -> Model
setKeyboardEntryType keyboardEntry model =
    let
        stateInfo = model.stateInfo
        newStateInfo = {stateInfo | keyboardEntryType = keyboardEntry}
    in
        {model | stateInfo = newStateInfo}

setGridUpdateStruct : Model -> Model
setGridUpdateStruct model =
    let
        position : Int
        position = model.squareSelectedInfo.selected

        value : String
        value = Maybe.withDefault "" (List.Extra.getAt position model.crossword.grid)

        method : String
        method =
            if List.member position model.crossword.revealedGrid then
                "revealed"
            else
                "manual"

        g : GridUpdateStruct
        g = {position = (String.fromInt position), value = value, method = method}

        stateInfo = model.stateInfo
        newStateInfo = {stateInfo | gridUpdateStruct = g}
    in
        {model | stateInfo = newStateInfo}


--------------------------------------------------
--------------------------------------------------
-- DECODE JSON INFORMATION
--------------------------------------------------
--------------------------------------------------

decodeCrosswordJsonToModel : Json.Decode.Decoder CrosswordModel
decodeCrosswordJsonToModel = 
    let
        gridSizeDecoder : Json.Decode.Decoder GridSize
        gridSizeDecoder =
            Json.Decode.succeed GridSize
                |> required "cols" Json.Decode.int
                |> required "rows" Json.Decode.int

        cluesDecoder : Json.Decode.Decoder Clues
        cluesDecoder =
            Json.Decode.succeed Clues
                |> required "across" (Json.Decode.list Json.Decode.string)
                |> required "down"   (Json.Decode.list Json.Decode.string)
    in
        Json.Decode.succeed CrosswordModel
            |> required "size" gridSizeDecoder
            |> required "clues" cluesDecoder
            |> required "grid" (Json.Decode.list Json.Decode.string)
            |> required "gridnums" (Json.Decode.list Json.Decode.int)
            |> required "title" (Json.Decode.string)
            |> optional "answerGrid" (Json.Decode.list Json.Decode.string) []
            |> optional "revealedGrid" (Json.Decode.list Json.Decode.int) []
