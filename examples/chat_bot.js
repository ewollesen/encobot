var Bot    = require('../index');
var Auth = require("../auth");
var bot = new Bot(Auth.auth, Auth.userid, Auth.roomid);

bot.on('speak', function (data) {
   // Get the data
   var name = data.name;
   var text = data.text;

   // Respond to "/hello" command
   if (text.match(/^\/hello$/)) {
      bot.speak('Hey! How are you '+name+' ?');
   }
});
