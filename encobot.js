var Bot = require('./index');
var Auth = require("./auth");
var bot = new Bot(Auth.auth, Auth.userid, Auth.roomid);

bot.debug = false;

var owners = [
  "4ee8335da3f7517e38000f6c" // @gt5cars
];

bot.on('roomChanged', function (data) {
    bot.modifyName("encobot", function (data) {
        console.log("encobot updated his name:", data);
    });
    bot.modifyLaptop("linux", function (data) {
        console.log("encobot updated his laptop:", data);
    });
    bot.setAvatar(6, function (data) {
        console.log("encobot updated his avatar:", data);
    });
    bot.modifyProfile({about: 'This bot belongs to: encoded'},
                      function (data) {
                          console.log("encobot updated his profile:", data);
                      });
});

bot.on('speak', function (data) {
   // Get the data
   var name = data.name;
   var text = data.text;
   var userid = data.userid;

   for (var i=0; i<owners.length; i++) {
      if (userid == owners[i]) {
        if (text.match(/^\/hello$/)) {
          bot.speak('Hey! How are you '+name+' ?');
          console.log("encobot said hello to " + name);
          break;
        }
        if (text.match(/^\/encobot$/)) {
          bot.speak('I am encobot! I come in peace to destroy the world.');
          console.log("encobot identified itself to " + name);
          break;
        }
      }
   }
});

bot.on('newsong', function (data) { bot.vote('up'); });
bot.on('registered', function (data) {
    console.log('Someone registered', data);
});


bot.tcpListen(8080, "127.0.0.1");

bot.on("tcpConnect", function (socket) { });
bot.on("tcpMessage", function (socket, msg) {
    if ((data = msg.match(/^setAvatar (\d+)/))) {
        var i = parseInt(data[1]);
        bot.setAvatar(i, function (data) {
            if (data.success) {
                socket.write(">> " + i + "\n");
            } else {
                socket.write(">> " + data.err + "\n");
            }
        });
    }
    if ((data = msg.match(/^modifyName (.+)/))) {
        var s = data[1];
        bot.modifyName(s, function (data) {
            if (data.success) {
                socket.write(">> " + s + "\n");
            } else {
                socket.write(">> " + data.err + "\n");
            }
        });
    }
    if ((data = msg.match(/^modifyLaptop (.+)/))) {
        var s = data[1];
        bot.modifyLaptop(s, function (data) {
            if (data.success) {
                socket.write(">> " + s + "\n");
            } else {
                socket.write(">> " + data.err + "\n");
            }
        });
    }
    if (msg.match(/^addDj\r$/)) {
        bot.playlistAdd("default", "4e1759b999968e76a4002cfc", function (data) {
            console.log("playlistAdd:", data);
        });
        bot.addDj(function (data) {
            console.log("Add DJ:", data);
            if (data.success) {
                socket.write(">> " + s + "\n");
            } else {
                socket.write(">> " + data.err + "\n");
            }
        });
    }
});
bot.on("tcpEnd", function (socket) { });
