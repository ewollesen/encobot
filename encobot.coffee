_und = require("underscore")
Bot = require("ttapi")
Config = _und.extend({}, require("./defaults"), require(process.argv[2]))
Db = require("mongodb").Db
Connection = require("mongodb").Connection
Server = require("mongodb").Server
Mu = require("Mu/mu")
spawn = require('child_process').spawn

responses = [
  {
    public: true
    regex: new RegExp("^(what(?:'?s?| is)? up,?|hello|hi|h[ei]ya?) #{Config.name}\\??", "i")
    func: (data) ->
      name = data.name
      bot.pickAndCompile bot.greetingResponses, {name: name}, (text) ->
        bot.speak text
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
  }, {
    public: false
    regex: new RegExp("^#{Config.name} (?:last )?seen (.+)", "i")
    func: (data, match) ->
      name = match[1]
      bot.lastSeen name, (seen) ->
        bot.speak(seen)
  }, {
    public: false
    regex: new RegExp("^#{Config.name} (?:last )?heard (.+)", "i")
    func: (data, match) ->
      artist = match[1]
      bot.lastHeard artist, (heard) ->
        bot.speak(heard)
  }, {
    public: true
    regex: new RegExp("^#{Config.name} tell me my fortune", "i")
    func: (data) ->
      bot.fortune (fortune) ->
        bot.speak(fortune)
  }
]

if Config.pgRating
  responses.push
    public: true
    regex: /\b(bitch(?:es)?|shit(?:er|ty)?|fuck(?:ing?|er|ed)?|cunt|asshole)\b/i
    func: (data) ->
      name = data.name
      bot.speak "Hey #{name}! Let's try to keep our PG rating, OK?"

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
    @debug = Config.debug ? false
    @greetingResponses = Config.greetingResponses ? []
    @on "speak", @handleSpeak
    @on "newsong", @handleNewSong
    @on "roomChanged", @handleRoomChanged
    @on "registered", @handleRegistered
    @on "nosong", @handleNoSong
    @on "update_votes", @handleUpdateVotes

    super auth, userid, roomid


  handleRoomChanged: (data) ->
    @checkAndCorrectSetup(data)
    @moderatorIds = data.room.metadata.moderator_id
    @markovBreak()

  handleRegistered: (data) ->
    @greet(data)
    @updateLastSeenDueToRegistered(data)

  handleNoSong: (data) ->
    @speak "Awww, I hate it when it's quiet in here."

  handleSpeak: (data) ->
    @checkForAndRespondToCommands(data)
    @updateLastSeenDueToSpeech(data)

  handleNewSong: (data) ->
    @recordNewSong(data)

  handleUpdateVotes: (data) ->
    @updateLastSeenDueToVote(data)

  recordNewSong: (data) ->
    dj = data.room.metadata.current_dj
    if dj is Config.userid
      @markovBreak()
      return

    unless data.room.metadata.current_song._id?
      console.log("Received a newsong notification without a song id!")
      console.log(data)

    @autoAwesome(data)
    @yoink(data)
    @markovPush(data)

  updateLastSeenDueToSpeech: (data) ->
    name = data.name
    text = data.text
    userId = data.userid

    @db = new Db("encobot", new Server("127.0.0.1", 27017, {}))
    @db.open (err, p_client) =>
      @db.collection "last_seen", (err, c) =>
        c.findOne {userId: userId}, (err, one) =>
          doc = if one then one else {userId: userId}
          doc.name = name
          doc.spoke = new Date
          doc.roomId = @roomId
          c.save doc
          @db.close()

  updateLastSeenDueToRegistered: (data) ->
    user = data.user[0].name
    userId = data.user[0].userid
    name = data.user[0].name

    @db = new Db("encobot", new Server("127.0.0.1", 27017, {}))
    @db.open (err, p_client) =>
      @db.collection "last_seen", (err, c) =>
        c.findOne {userId: userId}, (err, one) =>
          doc = if one then one else {userId: userId}
          doc.name = name
          doc.registered = new Date
          doc.roomId = @roomId
          c.save doc
          @db.close()

  # TODO: find the user's name from their userId
  updateLastSeenDueToVote: (data) ->
    votes = data.room.metadata.votelog

    @db = new Db("encobot", new Server("127.0.0.1", 27017, {}))
    @db.open (err, p_client) =>
      @db.collection "last_seen", (err, c) =>
        votes.forEach (vote) =>
          userId = vote[0]
          c.findOne {userId: userId}, (err, one) =>
            doc = if one then one else {userId: userId}
            doc.vote = new Date
            doc.roomId = @roomId
            c.save doc
            @db.close()

  checkForAndRespondToCommands: (data) ->
    name = data.name
    text = data.text
    userid = data.userid

    for response in responses
      if ((match = text.match(response.regex)))
        if response.public or @isOwner(userid)
          console.log "encobot responds to #{response.regex} from #{name}"
          response.func(data, match)
          break

  checkAndCorrectSetup: ->
    modified = false

    @userInfo (data) =>
      if Config.name isnt data.name
        modified = true
        @modifyName Config.name, (r) ->
          if r.success
            console.log "encobot updated her name to #{Config.name}"
          else
            console.log "Error updating name", r

      if Config.avatar isnt data.avatarid
        modified = true
        @setAvatar Config.avatar, (r) ->
          if r.success
            console.log "encobot updated her avatar to #{Config.avatar}"
          else
            console.log "Error updating avatar", r

      if Config.laptop isnt data.laptop
        modified = true
        @modifyLaptop Config.laptop, (r) ->
          if r.success
            console.log "encobot updated her laptop to #{Config.laptop}"
          else
            console.log "Error updating laptop", r

      if modified
        @modifyProfile
          about: "This encobot belongs to: #{Config.owner}."
        , (r) ->
          if r.success
            console.log "encobot updated her owner to #{Config.owner}"
          else
            console.log "Error updating profile", r

  fortune: (cb) ->
    args = ["-s", "fortunes"]
    args.push("-a") unless Config.pgRating
    fortune = spawn("fortune", args)
    fortune.stdout.on "data", (data) =>
      cb(data)

  lastSeen: (name, cb) ->
    @db = new Db("encobot", new Server("127.0.0.1", 27017, {}))
    @db.open (err, p_client) =>
      @db.collection "last_seen", (err, c) =>
        c.findOne {roomId: @roomId, name: new RegExp("#{name}", "i")}, (err, doc) =>
          if doc
            latest = new Date Math.max(doc.vote ? 0, doc.spoke ? 0, doc.registered ? 0)
            seen = "I last saw #{doc.name} at #{latest.toString()}"
          else
            seen = "I've not seen #{name} before."
          @db.close()
          cb(seen)

  lastHeard: (artist, cb) ->
    @db = new Db("encobot", new Server("127.0.0.1", 27017, {}))
    @db.open (err, p_client) =>
      @db.collection "markov_chain", (err, c) =>
        c.find {roomId: @roomId, artist: new RegExp("^#{artist}$", "i")}, (err, c) =>
          c.sort({heard: -1}).limit(1).nextObject (err, doc) =>
            if doc
              heard = "I last heard \"#{doc.title}\" by #{doc.artist} at #{doc.heard.toString()}"
            else
              heard = "I've not heard #{artist} before."
            @db.close()
            cb(heard)

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
      # TODO: move me to a sass mode or something
      # else if v > 0.93 and v <= 0.95
      #   @speak("This song STINKS!")
      #   @vote "down"
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
      @db.collection "markov_chain", (err, c) =>
        c.drop (err, result) =>
          @state.prevSong = undefined
          console.log("cleared markov_chain")
          @db.close()
          cb(err, result)

  markovPush: (data) ->
    songId = data.room.metadata.current_song._id
    roomId = data.room.roomid
    artist = data.room.metadata.current_song.metadata.artist
    title = data.room.metadata.current_song.metadata.song
    @db = new Db("encobot", new Server("127.0.0.1", 27017, {}))

    @db.open (err, p_client) =>
      @db.collection "markov_chain", (err, c) =>
        doc =
          songId: songId
          roomId: roomId
          artist: artist
          title: title
          heard: new Date
        doc.prevSong = @state.prevSong if @state.prevSong
        c.insert doc, (err, docs) ->
          console.log("Appended a link to the markov chain")
          console.log("Now playing: #{title} - #{artist}")

        @state.prevSong = songId
        @db.close()

  markovBreak: ->
    @state.prevSong = undefined

  isOwner: (userId) ->
    userId in @moderatorIds or userId in Config.ownerIds


bot = new Encobot(Config.auth, Config.userid, Config.roomid)


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
