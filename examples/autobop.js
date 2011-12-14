/**
 * Each time a song start, the bot vote up.
 */

var Bot    = require('../index');

var bot = new Bot(AUTH, USERID, ROOMID);

bot.on('newsong', function (data) { bot.vote('up'); });
