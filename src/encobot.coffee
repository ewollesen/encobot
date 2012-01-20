_und = require("underscore")
Bot = require("ttapi")
Config = _und.extend({}, require("./defaults"), require(process.argv[2]))
Db = require("mongodb").Db
Connection = require("mongodb").Connection
Server = require("mongodb").Server
Mu = require("Mu/mu")
spawn = require('child_process').spawn
defer = require("node-promise").defer
log4js = require("log4js")


log4js.addAppender(log4js.fileAppender(Config.logfile ? "log/encobot.log"), "encobot")
log = log4js.getLogger("encobot");
log.setLevel("DEBUG");

Config.commandPrefix = ->
  "(?:/|#{Config.name} )"

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
    regex: new RegExp("^#{Config.commandPrefix()}identify( yourself)?", "i")
    func: (data) ->
      bot.speak "I am encobot! I come in peace to destroy the world. See http://xmtp.net/~encoded/encobot for details."
  }, {
    public: false
    regex: new RegExp("^#{Config.commandPrefix()}autoAwesome(?: (on|off)?)?", "i")
    func: (data, match) ->
      switch match[1]
        when "on"
          bot.state.autoAwesome = true
        when "off"
          bot.state.autoAwesome = false
      s = if bot.state.autoAwesome then "on" else "off"
      bot.speak("autoAwesome: #{s}")
  }, {
    public: true
    regex: new RegExp("^#{Config.commandPrefix()}(?:last )?seen (.+)", "i")
    func: (data, match) ->
      name = match[1]
      bot.lastSeen name, (seen) ->
        bot.speak(seen)
  }, {
    public: true
    regex: new RegExp("^#{Config.commandPrefix()}(?:last )?heard (.+)", "i")
    func: (data, match) ->
      artist = match[1]
      bot.lastHeard artist, (heard) ->
        bot.speak(heard)
  }, {
    public: true
    regex: new RegExp("^#{Config.commandPrefix()}(?:tell me my )?fortune", "i")
    func: (data) ->
      bot.fortune (fortune) ->
        bot.speak(fortune)
  }, {
    public: true
    regex: new RegExp("^#{Config.commandPrefix()}(?:tell me a )?joke", "i")
    func: (data) ->
      bot.joke (fortune) ->
        bot.speak(fortune)
  }, {
    public: true
    regex: new RegExp("^#{Config.commandPrefix()}dance", "i")
    func: (data) ->
      bot.dance (dance) ->
        bot.speak(dance)
  }, {
    public: true
    regex: new RegExp("^make me a sandwich", "i")
    func: (data) ->
      bot.speak("Make it yourself.")
  }, {
    public: false
    regex: new RegExp("^sudo make me a sandwich", "i")
    func: (data) ->
      bot.speak("OK.")
  }, {
    public: true
    regex: new RegExp("^sudo make me a sandwich", "i")
    func: (data, match, name) ->
      bot.speak("#{name} is not in the sudoers file. This incident will be reported.")
  }, {
    public: false
    regex: new RegExp("^#{Config.commandPrefix()}(?:give me a )?hug", "i")
    func: (data, match, name) ->
      bot.speak("/me hugs #{name}.")
  }, {
    public: true
    regex: new RegExp("^#{Config.commandPrefix()}(?:give me a )?hug", "i")
    func: (data) ->
      bot.speak("I don't hug strangers.")
  }, {
    public: false
    regex: new RegExp("^#{Config.commandPrefix()}genuflect(?: before me)?", "i")
    func: (data, match, name) ->
      bot.speak("/me takes a knee in reverence to #{name}.")
  }, {
    public: false
    regex: new RegExp("^#{Config.commandPrefix()}skip", "i")
    func: (data, match, name) ->
      bot.stopSong()
  }, {
    public: false
    regex: new RegExp("^#{Config.commandPrefix()}playlist clear", "i")
    func: (data, match, name) ->
      bot.playlistClear.then ->
        bot.speak("Playlist cleared")
  }, {
    public: false
    regex: new RegExp("^#{Config.commandPrefix()}playlist load", "i")
    func: (data, match, name) ->
      bot.playlistLoad()
      bot.speak("Playlist loaded")
  }, {
    public: true
    regex: /\b(bitch(?:es|y)?|shit(?:ty|tiest|ter)?|fuck(?:ing?|er|ed)?|cunt|asshole)\b/i
    func: (data) ->
      return unless Config.pgRating
      name = data.name
      bot.speak "Hey #{name}! Let's try to keep our PG rating, OK?"
  }
]

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
    @roomName = "Unknown Room"
    @state =
      autoAwesome: Config.autoAwesome ? true
    @debug = Config.debug ? false
    @greetingResponses = Config.greetingResponses ? []
    @on "speak", @handleSpeak
    @on "newsong", @handleNewSong
    @on "ready", @handleReady
    @on "roomChanged", @handleRoomChanged
    @on "registered", @handleRegistered
    @on "deregistered", @handleDeregistered
    @on "nosong", @handleNoSong
    @on "update_votes", @handleUpdateVotes
    @db = new Db("encobot", new Server("127.0.0.1", 27017, {}))

    super auth, userid, roomid


  handleReady: (data) ->
    log.info("encobot ready")
    @checkAndCorrectSetup(data)

  handleRoomChanged: (data) ->
    log.debug("Entered room \"#{data.room.name}\"")
    @moderatorIds = data.room.metadata.moderator_id
    @roomName = data.room.name
    @markovBreak()

  handleRegistered: (data) ->
    @greet(data)
    @updateLastSeenDueToRegistered(data)

  handleDeregistered: (data) ->
    @returnToRoomIfLeft(data)

  handleNoSong: (data) ->
    @speak "Awww, I hate it when it's quiet in here."

  handleSpeak: (data) ->
    @checkForAndRespondToCommands(data)
    @updateLastSeenDueToSpeech(data)

  handleNewSong: (data) ->
    @autoAwesome(data)
    @recordNewSong(data)

  handleUpdateVotes: (data) ->
    @updateLastSeenDueToVote(data)

  returnToRoomIfLeft: (data) ->
    if Config.name is data.user[0].name
      log.debug("I've left the room. I wonder why?")
      process.exit(1);

  recordNewSong: (data) ->
    dj = data.room.metadata.current_dj
    if dj is Config.userid
      @markovBreak()
      return

    unless data.room.metadata.current_song._id?
      log.debug("Received a newsong notification without a song id!")
      log.debug(data)

    @yoink(data)
    @markovPush(data)

  updateLastSeenDueToSpeech: (data) ->
    name = data.name
    text = data.text
    userId = data.userid

    @db.open (error, db) =>
      @db.collection "last_seen", (error, c) =>
        c.findOne {userId: userId}, (error, one) =>
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

    @db.open (error, db) =>
      @db.collection "last_seen", (error, c) =>
        c.findOne {userId: userId}, (error, one) =>
          doc = if one then one else {userId: userId}
          doc.name = name
          doc.registered = new Date
          doc.roomId = @roomId
          c.save doc
          @db.close()

  updateLastSeenDueToVote: (data) ->
    votes = data.room.metadata.votelog

    @db.open (error, db) =>
      @db.collection "last_seen", (error, c) =>
        votes.forEach (vote) =>
          userId = vote[0]
          c.findOne {userId: userId}, (error, one) =>
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
          log.debug "encobot responds to #{response.regex} from #{name}"
          response.func(data, match, name)
          break

  checkAndCorrectSetup: ->
    modified = false

    @userInfo (data) =>
      if Config.name isnt data.name
        modified = true
        @modifyName Config.name, (r) ->
          if r.success
            log.debug "encobot updated her name to #{Config.name}"
          else
            log.error "Error updating name", r

      if Config.avatar isnt data.avatarid
        modified = true
        @setAvatar Config.avatar, (r) ->
          if r.success
            log.debug "encobot updated her avatar to #{Config.avatar}"
          else
            log.error "Error updating avatar", r

      if Config.laptop isnt data.laptop
        modified = true
        @modifyLaptop Config.laptop, (r) ->
          if r.success
            log.debug "encobot updated her laptop to #{Config.laptop}"
          else
            log.error "Error updating laptop", r

      if modified
        @modifyProfile
          about: "This encobot belongs to: #{Config.owner}. See http://xmtp.net/~encoded/encobot for details."
        , (r) ->
          if r.success
            log.debug "encobot updated her owner to #{Config.owner}"
          else
            log.error "Error updating profile", r

  fortune: (cb) ->
    args = ["-s", "fortunes"]
    args.push("-a") unless Config.pgRating
    fortune = spawn("fortune", args)
    fortune.stdout.on "data", (data) =>
      cb(data)

  joke: (cb) ->
    args = ["-s", "humorists"]
    args.push("-a") unless Config.pgRating
    fortune = spawn("fortune", args)
    fortune.stdout.on "data", (data) =>
      cb(data)

  dance: (cb) ->
    @pickAndCompile Config.dances, {name: Config.name}, (dance) =>
      cb(dance)

  lastSeen: (name, cb) ->
    @db.open (error, db) =>
      @db.collection "last_seen", (error, c) =>
        c.findOne {roomId: @roomId, name: new RegExp("#{name}", "i")}, (error, doc) =>
          if doc
            latest = new Date Math.max(doc.vote ? 0, doc.spoke ? 0, doc.registered ? 0)
            seen = "I last saw #{doc.name} at #{latest.toString()}"
          else
            seen = "I've not seen #{name} before."
          @db.close()
          cb(seen)

  lastHeard: (artist, cb) ->
    @db.open (error, db) =>
      @db.collection "markov_chain", (error, c) =>
        log.error("Error in lastHeard: ", error) if error
        c.find {roomId: @roomId, artist: new RegExp("^#{artist}$", "i")}, (error, c) =>
          c.sort({heard: -1}).limit(1).nextObject (error, doc) =>
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
        room: @roomName
        , (text) =>
          @speak text

  autoAwesome: (data) ->
    return unless @state.autoAwesome

    @afterPause Math.randInt(5, 30), =>
      return unless @currentSongId
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
        @playlistDel(length - 1)

  markovClear: (data, cb) ->
    @db.open (error, db) =>
      @db.collection "markov_chain", (error, c) =>
        c.drop (error, result) =>
          @state.prevSong = undefined
          log.info("cleared markov_chain")
          @db.close()
          cb(error, result)

  markovPush: (data) ->
    songId = data.room.metadata.current_song._id
    roomId = data.room.roomid
    artist = data.room.metadata.current_song.metadata.artist
    title = data.room.metadata.current_song.metadata.song

    @db.open (error, db) =>
      @db.collection "markov_chain", (error, c) =>
        doc =
          songId: songId
          roomId: roomId
          artist: artist
          title: title
          heard: new Date
        doc.prevSong = @state.prevSong if @state.prevSong
        c.insert doc, (error, docs) ->
          log.debug("Appended a link to the markov chain")
          log.debug("Now playing: #{title} - #{artist}")

        @state.prevSong = songId
        @db.close()

  markovBreak: ->
    @state.prevSong = undefined

  isOwner: (userId) ->
    userId in @moderatorIds or userId in Config.ownerIds

  # TODO: set me up with a callback and check for errors
  playlistClear: ->
    @_deferred (dfd) =>
      @playlistAll (data) =>
        return dfd.reject(data) unless data.success

        for song in data.list
          @playlistDel 0, (data) =>
            return dfd.reject(data) unless data.success
            log.debug("removed song with id: #{data}")

        # I am called too early
        dfd.resolve(data)

  playlistDel: (index) ->
    @_deferred (dfd) =>
      @playlistRemove index, (data) =>
        return dfd.reject(data) unless data.success
        log.debug("playlist remove success #{index} #{data.fileid}")
        dfd.resolve(data)

  # TODO: set me up with a callback and check for errors
  playlistLoad: ->
    @db.collection "markov_chain", (error, c) =>
      log.debug("using roomId: #{@roomId}")
      c.find {roomId: @roomId}, (error, c) =>
        c.each (error, doc) =>
          if doc and doc.songId
            @playlistAdd doc.songId, (error, result) =>
              log.debug("added #{doc.songId}")
          else
            log.debug("doc has no songId:", doc)
      @db.close()

  reportError: (data) ->
    log.error(data)

  _deferred: (f) ->
    dfd = defer()
    f(dfd)
    dfd.promise

bot = new Encobot(Config.auth, Config.userid, Config.roomid)


bot.tcpListen Config.tcpConsolePort ? 2222, "127.0.0.1"
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
    idx = 0
    bot.playlistAll (data) ->
      for song in data.list
        idx += 1
        s = "\"#{song.metadata.song}\" - #{song.metadata.artist}"
        socket.write(">> #{idx}: #{s}\n")
    log.debug("playlist fin")

  if data = msg.match(/^playlist del ([0-9]+)\r$/)
    index = Math.max(0, parseInt(data[1]) - 1)
    bot.playlistDel(index).then (data) ->
      socket.write ">> OK\n"

  if msg.match(/^playlist clear\r$/)
    bot.playlistClear().then ->
      socket.write(">> playlist cleared\n")
  if msg.match(/^addDj\r$/)
    bot.playlistAdd "default", "4e1759b999968e76a4002cfc", (data) ->
      log.debug "playlistAdd:", data

    bot.addDj (data) ->
      log.debug "Add DJ:", data
      if data.success
        socket.write ">> " + s + "\n"
      else
        socket.write ">> " + data.err + "\n"
  if msg.match(/^remDj\r$/)
    bot.remDj (data) ->
      log.debug "Rem DJ:", data
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
      log.debug "Speak:", data
      if data.success
        socket.write ">> " + s + "\n"
      else
        socket.write ">> " + data.err + "\n"
  if msg.match(/^markov clear\r$/)
    bot.markovClear data, (error, result) ->
      socket.write(">> markov cleared\n")
  if msg.match(/^randInt\r$/)
    socket.write(">> #{Math.randInt(1,5)}\n")
  if msg.match(/^choice\r$/)
    socket.write(">> #{[1,2,3,4,5].choice()}\n")
  if msg.match(/^skip\r$/)
    bot.stopSong (data) ->
      socket.write(">> skip\n")
  if msg.match(/^room\r$/)
    socket.write(">> room: \"#{bot.roomName}\" #{bot.roomId}\n")
  if msg.match(/^roomInfo\r$/)
    bot.roomInfo (data) ->
      log.debug("roomInfo", data)
      socket.write(">> roomInfo has been logged\n")
