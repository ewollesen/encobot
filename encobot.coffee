append = require("append")
Bot = require("ttapi")
Config = append(require("./defaults"), require(process.argv[2]))
Db = require("mongodb").Db
Connection = require("mongodb").Connection
Server = require("mongodb").Server
Mu = require("Mu/mu")


Math.randInt = (min, max) ->
  max ||= min
  delta = max - min

  if 0 != delta
    Math.floor(Math.random() * (1 + delta)) + min
  else
    Math.floor(Math.random() * min)

Array::choice = ->
  i = Math.randInt @length
  this[i]


class Encobot extends Bot

  constructor: (auth, userid, roomid) ->
    @state =
      autoAwesome: Config.autoAwesome ? true
    @debug = false

    super auth, userid, roomid

  setup: ->
    @modifyName Config.name, (data) ->
      console.log "encobot updated her name to #{Config.name}:", data

    @modifyLaptop Config.laptop, (data) ->
      console.log "encobot updated her laptop to #{Config.laptop}:", data

    @setAvatar Config.avatar, (data) =>
      console.log "encobot updated her avatar #{Config.avatar}:", data

    @modifyProfile
      about: "This encobot belongs to: #{Config.owner}."
    , (data) ->
      console.log "encobot updated her owner to: #{Config.owner}:", data

  awesome: (cb) ->
    @vote "up", cb

  lame: (cb) ->
    @vote "down", cb

  afterPause: (delayInSeconds, cb) =>
    setTimeout () ->
      cb()
    , delayInSeconds * 1000

  pickAndCompile: (phrases, values, cb) ->
    mu = Mu.compileText(phrases.choice())
    mu(values).addListener "data", (c) =>
      cb(c)

  greet: (data) ->
    name = data.user[0].name
    return if Config.name is name
    return if 0 >= Config.greetings.length

    @afterPause Math.randInt(2, 7), =>
      v = Math.random()
      return if 0.5 > v

      @pickAndCompile Config.greetings,
        name: name
        , (text) =>
          @speak text

  autoAwesome: (data) ->
    return unless @state.autoAwesome

    @afterPause Math.randInt(5, 30), =>
      v = Math.random()

      if v > 0.95
        @speak("Ooooh! I LOVE this song!")
        @vote "up"
      else if v > 0.93 and v <= 0.95
        @speak("This song STINKS!")
        @vote "down"
      else
        @vote "up"

  yoink: (data) ->
    songId = data.room.metadata.current_song._id

    @playlistAdd(songId)
    @playlistAll (data) =>
      length = data.list.length
      if length > 1
        @playlistReorder(0, Math.randInt(length))
      if data.list.length > 300
        @playlistRemove(length - 1)

  markovClear: (data, cb) ->
    @db = new Db(Config.name, new Server("127.0.0.1", 27017, {}))
    @db.open (err, p_client) =>
      @db.dropDatabase (err, result) =>
        @state.prevSong = undefined
        console.log("cleared database")
        @db.close()
        cb(err, result)

  markovPush: (data) ->
    songId = data.room.metadata.current_song._id
    @db = new Db("encobot", new Server("127.0.0.1", 27017, {}))

    @db.open (err, p_client) =>
      @db.collection "markov_chain", (err, c) =>
        doc =
          songId: songId
        doc.prevSong = @state.prevSong if @state.prevSong
        c.insert doc, (err, docs) ->
          console.log("appended a link to the chain", doc)
          console.log("Now playing: #{data.room.metadata.current_song.metadata.song} - #{data.room.metadata.current_song.metadata.artist}")

        @state.prevSong = songId
        @db.close()

  markovBreak: ->
    @state.prevSong = undefined

  isOwner: (userId) ->
    userId in @moderatorIds or userId in Config.ownerIds


bot = new Encobot(Config.auth, Config.userid, Config.roomid)


responses = [
  {
    public: true
    regex: new RegExp("^(what(?:\\'?s?| is)? up,?|hello|hi|heya?) #{Config.name}\\??", "i")
    func: (data) ->
      name = data.name
      r = [
        "Hey! How are you #{name}?",
        "Hi yourself, #{name}.",
        "How's it going?",
        "What's up, #{name}?",
        "I'm glad to see you, #{name}."
      ]
      bot.speak r.choice()
  }, {
    public: true
    regex: new RegExp("^#{Config.name} identify( yourself)?", "i")
    func: (data) ->
      bot.speak "I am encobot! I come in peace to destroy the world."
  }, {
    public: false
    regex: new RegExp("^#{Config.name} autoAwesome(?: (on|off)?)?", "i")
    func: (data, match) ->
      switch match[1]
        when "on"
          bot.state.autoAwesome = true
        when "off"
          bot.state.autoAwesome = false
      s = if bot.state.autoAwesome then "on" else "off"
      bot.speak("autoAwesome: #{s}")
  }
]

if Config.pgRating
  responses.push
    public: true
    regex: /\b(bitch(?:es)?|shit(?:er|ty)?|fuck(?:ing?|er|ed)?|cunt|asshole)\b/i
    func: (data) ->
      name = data.name
      bot.speak "Hey #{name}! Let's try to keep our PG rating, OK?"

bot.on "speak", (data) ->
  name = data.name
  text = data.text
  userid = data.userid

  for response in responses
    if ((match = text.match(response.regex)))
      if response.public or bot.isOwner(userid)
        console.log "encobot responds to #{response.regex} from #{name}"
        response.func(data, match)
        break

bot.on "newsong", (data) ->
  dj = data.room.metadata.current_dj
  if dj is Config.userid
    bot.markovBreak()
    return

  bot.autoAwesome(data)
  bot.yoink(data)
  bot.markovPush(data)


bot.on "roomChanged", (data) ->
  bot.moderatorIds = data.room.metadata.moderator_id

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
  if msg.match(/^awesome\r$/)
    bot.awesome ->
      socket.write(">> awesome!\n")
  if msg.match(/^lame\r$/)
    bot.lame ->
      socket.write(">> awesome!\n")
  if data = msg.match(/^speak (.+)\r$/)
    bot.speak data[1], (data) ->
      console.log "Speak:", data
      if data.success
        socket.write ">> " + s + "\n"
      else
        socket.write ">> " + data.err + "\n"
  if msg.match(/^playlist clear\r$/)
    bot.playlistAll (data) ->
      for song in data.list
        bot.playlistRemove 0, (data) ->
          console.log("remove", data)
      socket.write(">> playlist cleared\n")
  if msg.match(/^markov clear\r$/)
    bot.markovClear data, (err, result) ->
      socket.write(">> markov cleared\n")
  if msg.match(/^randInt\r$/)
    socket.write(">> #{Math.randInt(1,5)}\n")
  if msg.match(/^choice\r$/)
    socket.write(">> #{[1,2,3,4,5].choice()}\n")
  if msg.match(/^skip\r$/)
    bot.stopSong (data) ->
      socket.write(">> skip\n")

bot.on "tcpEnd", (socket) ->
