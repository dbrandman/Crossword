# Collaborative New York Times Crossword solver

Many people enjoy doing crosswords with their friends and family. But self-isolation (due to COVID-19) means less crosswords with friends. So I built a collaborative NYT crossword app. You can see what your friends are doing in real time! Any changes they make will be available on your screen, and you can see what part of the board they're focusing on.

Note that this version is not mobile friendly.

The project is designed as a single-page application written in [elm](https://elm-lang.org/). The application reads JSON files of exisiting crosswords that are available online (such as [here](https://www.xwordinfo.com/JSON/) and [here](https://github.com/doshea/nyt_crosswords). The elm application talks to a back-end [Flask-SocketIO](https://flask-socketio.readthedocs.io/en/latest/) using [Redis](https://redis.io/) as a cache storing system. Once a connection is made, the crossword is downloaded from a REST interface, and the real-time updates use websockets. To get the look-and-feel just right, I made some slight modifications to the [Milligram](https://milligram.io/) css framework.

## User instructions

* Use the arrow keys or the mouse to move the selected square
* To change directions of letter entry, press the space bar (or double click)

# Requirements

* Elm 0.19.1
* Redis
* Python 3, Redis, Flask, Flask-SocketIO
* Any webserver you'd like (`python -m http.server` will do just nicely)

# Setting up

1. There are three separate files to configure:
    1. Edit `elm/Crossword.elm` to point the URL to the websocket server
    2. Edit `index.html` to point it to the URL of the websocket server
2. Compile `elm/Crossword.elm` by running the Makefile. 
3. Run `websocketServer.py`. You can specify the location of a JSON file using a command-line argument
4. You and your friends should now launch index.html. Enjoy!

# Known issues

Not so much a bug per se, but I can't figure out why the `Cmd` associated with `KeyDown` in the `update` function doesn't fire when the `Msg` is interpreted. One would expec the `Cmd` to fire once the model is updated, not on the next model update cycle. This means that your information only gets broadcasted when the next event fires. If anyone knows why, please let me know!



