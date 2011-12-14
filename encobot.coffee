Bot = require("./index")
Auth = require("./auth")
bot = new Bot(Auth.auth, Auth.userid, Auth.roomid)
Db = require("mongodb").Db
Connection = require("mongodb").Connection
Server = require("mongodb").Server

bot.debug = false

bot.config =
  "autonod": true

owners = [
  "4ed7cb734fe7d06007000032", # Ronnie Bjarnason
  "4ed7bd8e4fe7d01c80000628", # Joseph LeBaron
  "4ed6b0ec4fe7d01c8000014b", # Mike Metcalf
  "4edfa46e4fe7d029450023f7"  # Eric Wollesen
]

bot.on "roomChanged", (data) ->
  bot.modifyName "encobot", (data) ->
    console.log "encobot updated his name:", data

  bot.modifyLaptop "linux", (data) ->
    console.log "encobot updated his laptop:", data

  bot.setAvatar 6, (data) ->
    console.log "encobot updated his avatar:", data

  bot.modifyProfile
    about: "This bot belongs to: encoded"
  , (data) ->
    console.log "encobot updated his profile:", data

responses = [
  {
    public: true
    regex: /^(what(?:\'?s?| is)? up,?|hello|hi|heya?) encobot\??$/
    func: (data) ->
      name = data.name
      bot.speak "Hey! How are you #{name}?"
  }, {
    public: true
    regex: /^encobot identify( yourself)?$/
    func: (data) ->
      bot.speak "I am encobot! I come in peace to destroy the world."
  }, {
    public: true
    regex: /\b(shit|fuck|cunt|asshole)\b/
    func: (data) ->
      name = data.name
      bot.speak "Hey #{name}! Let's try to keep our PG rating, OK?"
  }, {
    public: false
    regex: /^encobot autonod(?: (on|off)?)?$/
    func: (data, match) ->
      switch match[1]
        when "on"
          bot.config.autonod = true
        when "off"
          bot.config.autonod = false
      s = if bot.config.autonod then "on" else "off"
      bot.speak("encobot autonod: #{s}")
  }, {
    public: false
    regex: /^encobot playlist clear$/
    func: (data) ->
      bot.playlistAll (data) ->
        for song in data.list
          bot.playlistRemove 0, (data) ->
            console.log("remove", data)
        bot.speak("encobot playlist cleared")
  }
]

bot.greet = (name) ->
  greetings = [
    "Hey #{name}, long time no see!",
    "Woo! #{name}'s here, now we can start the party!",
    "/me shakes her booty across the floor to dance next to #{name}."
  ]

  i = Math.floor(Math.random() * greetings.length)
  bot.speak greetings[i]

bot.on "speak", (data) ->
  name = data.name
  text = data.text
  userid = data.userid

  for response in responses
    if ((match = text.match(response.regex)))
      console.log("matched against #{response.regex}")
      if response.public or userid in owners
        console.log "encobot responds to #{response.regex} from #{name}"
        response.func(data, match)
        break

bot.yoink = (data) ->
  songId = data.room.metadata.current_song._id
  bot.playlistAdd(songId)
  bot.playlistAll (data) ->
    length = data.list.length
    if length > 1
      bot.playlistReorder(0, Math.floor(Math.random() * length))
    if data.list.length > 300
      bot.playlistRemove(length - 1)

bot.autonod = (data) ->
  return unless bot.config.autonod

  v = Math.random()

  if v > 0.95
    bot.speak("Ooooh! I LOVE this song!")
    bot.vote "up"
  else if v > 0.93 and v <= 0.95
    bot.speak("This song STINKS!")
    bot.vote "down"
  else
    bot.vote "up"

bot.on "newsong", (data) ->
  bot.yoink(data)
  bot.autonod(data)

bot.greet = (name) ->
  return if "encobot" is name

  v = Math.random()
  if v > 0.75
    bot.greet(name)

bot.on "registered", (data) ->
  bot.greet(data)

bot.on "nosong", (data) ->
  bot.speak "Awww, I hate it when it's quiet in here."

bot.tcpListen 8080, "127.0.0.1"
bot.on "tcpConnect", (socket) ->
  socket.write ">> welcome to encobot console access\n"

bot.on "tcpMessage", (socket, msg) ->
  if data = msg.match(/^setAvatar (\d+)/)
    i = parseInt(data[1])
    bot.setAvatar i, (data) ->
      if data.success
        socket.write ">> " + i + "\n"
      else
        socket.write ">> " + data.err + "\n"
  if data = msg.match(/^modifyName (.+)/)
    s = data[1]
    bot.modifyName s, (data) ->
      if data.success
        socket.write ">> " + s + "\n"
      else
        socket.write ">> " + data.err + "\n"
  if data = msg.match(/^modifyLaptop (.+)/)
    s = data[1]
    bot.modifyLaptop s, (data) ->
      if data.success
        socket.write ">> " + s + "\n"
      else
        socket.write ">> " + data.err + "\n"
  if msg.match(/^playlist\r$/)
    bot.playlistAll (data) ->
      for song in data.list
        console.log("song", song)
        s = "\"#{song.metadata.song}\" - #{song.metadata.artist}"
        socket.write(">> #{s}\n")
  if msg.match(/^addDj\r$/)
    bot.playlistAdd "default", "4e1759b999968e76a4002cfc", (data) ->
      console.log "playlistAdd:", data

    bot.addDj (data) ->
      console.log "Add DJ:", data
      if data.success
        socket.write ">> " + s + "\n"
      else
        socket.write ">> " + data.err + "\n"
  if msg.match(/^remDj\r$/)
    bot.remDj (data) ->
      console.log "Rem DJ:", data
      if data.success
        socket.write ">> " + s + "\n"
      else
        socket.write ">> " + data.err + "\n"
  if data = msg.match(/^speak (.+)\r$/)
    bot.speak data[1], (data) ->
      console.log "Speak:", data
      if data.success
        socket.write ">> " + s + "\n"
      else
        socket.write ">> " + data.err + "\n"

bot.on "tcpEnd", (socket) ->