from flask import Flask, jsonify, escape, request, send_from_directory
from flask_redis import FlaskRedis
from flask_cors import CORS, cross_origin

from flask_socketio import SocketIO, join_room, emit, send

import sys
import json
import redis

VERBOSE = True

app = Flask(__name__)
cors = CORS(app)

socketio = SocketIO(app, cors_allowed_origins="*")

r = FlaskRedis(app)

##################################################
### Helper functions
##################################################

def displayBoard():
    grid = r.get("grid")
    rows = r.get("rows")
    cols = r.get("cols")

    ind = 0
    for i in range(rows):
        print ("|", end='')
        for j in range(cols):
            print(grid[ind], end='')
            ind+=1
        print ("|")

##################################################
### Flask functions to handle incoming requests
##################################################

@app.route('/crossword')
def handle_Crossword():
    cluesDown = r.lrange("cluesDown", 0, -1)
    cluesAcross = r.lrange("cluesAcross", 0, -1)
    cluesDown = [x.decode('utf-8') for x in cluesDown]
    cluesAcross = [x.decode('utf-8') for x in cluesAcross]

    grid = r.lrange("grid", 0, -1)
    grid = [x.decode('utf-8') for x in grid]

    answerGrid = r.lrange("answerGrid", 0, -1)
    answerGrid = [x.decode('utf-8') for x in answerGrid]

    cols = r.get("cols")
    cols = int(cols.decode("utf-8"))
    rows = r.get("rows")
    rows = int(rows.decode("utf-8"))

    gridNumbers = r.lrange("gridNumbers", 0, -1)
    gridNumbers = [int(x.decode('utf-8')) for x in gridNumbers]

    title = r.get("title")
    title = title.decode('utf-8')

    revealedGrid = r.lrange("revealedGrid", 0, -1)
    print("REVEALED GRID: " , revealedGrid, "TYPE: ", type(revealedGrid))
    revealedGrid = [int(x.decode('utf-8')) for x in revealedGrid]

    output = {
        "size" : { "rows" : rows, "cols" : cols },
        "clues" : {"across" : cluesAcross, "down" : cluesDown },
        "grid" : grid,
        "gridnums" : gridNumbers,
        "answerGrid" : answerGrid,
        "title": title,
        "revealedGrid":  revealedGrid
        }

    return output


@socketio.on('clientGridUpdate')
def handle_UpdateGrid(incomingJsonString):

    req = json.loads(incomingJsonString)
    print(req)
    
    if req['method'] == "manual":
        r.lset("grid", req['position'], req['value'])
    elif req['method'] == "revealed":
        r.lpush("revealedGrid", req['position'])

    print(incomingJsonString)

    socketio.emit('serverGridUpdate', incomingJsonString, include_self=False)

@socketio.on('clientPositionUpdate')
def handle_UpdatePosition(incomingJsonString):
    req = json.loads(incomingJsonString)
    r.hset("userHash", request.sid, req['position'])

    hashValues = [x.decode('utf-8') for x in r.hvals("userHash")]
    hashKeys   = [x.decode('utf-8') for x in r.hkeys("userHash")]

    jsonEntries = {"websocketID": hashKeys, "position" : hashValues}

    print(jsonEntries)

    socketio.emit('serverPositionUpdate', json.dumps(jsonEntries), include_self=True)


@socketio.on('connect')
def handle_connect():
    r.hset("userHash", request.sid, "0")
    emit('serverAssignID', request.sid)
    print("---------------------------")
    print("New Connection: " , request.sid)
    print("---------------------------")

@socketio.on('disconnect')
def handle_connect():
    r.hdel("userHash", request.sid)
    hashValues = [x.decode('utf-8') for x in r.hvals("userHash")]
    output = {"position" : hashValues}
    socketio.emit('serverPositionUpdate', json.dumps(output), include_self=False)

    print("---------------------------")
    print("DISCONNECTION: " , request.sid)
    print("---------------------------")



##################################################
### Initialization functions
##################################################

def initializeRedisFromJson(argv):

    if len(sys.argv) == 1:
        fileName = 'json/ExampleCrossword.json'

    else:
        fileName = sys.argv[1]


    with open(fileName, 'r') as JSON:

        jsonData = json.load(JSON)

    print("LOADED THE FOLLOWING FILE: " , fileName)

    r.flushdb()
    r.set("stateNumber", 0)
    r.set("cols", jsonData["size"]["cols"])
    r.set("rows", jsonData["size"]["rows"])
    r.rpush("answerGrid"  , *jsonData["grid"])
    r.rpush("cluesAcross" , *jsonData["clues"]["across"])
    r.rpush("cluesDown"   , *jsonData["clues"]["down"])
    r.rpush("gridNumbers" , *jsonData["gridnums"])

    r.set("title", jsonData["title"])
    
    r.lpush("revealedGrid", "-1")

    gridCopy = jsonData["grid"]
    for ind, thisLetter in enumerate(gridCopy):
        if thisLetter != '.':
            gridCopy[ind] = ' '

    r.lpush("grid", *gridCopy)

##################################################
### The main event
##################################################

if __name__ == "__main__":

    print("Initializing redis...")
    r = redis.Redis()

    print("Initializing Redis From Json...")
    initializeRedisFromJson(sys.argv)

    print("Running Flask...")
    app.run(host='0.0.0.0',debug=True)

    
    print("Done")
