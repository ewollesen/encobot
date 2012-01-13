encobot
-------

Prerequisites
=============

1. Node.js
2. Turntable-API (npm install ttapi)
3. coffee-script (npm install coffee-script)
4. underscore (npm install underscore)
5. Mu (npm install Mu)
6. log4js (npm install log4js)
7. node-mongodb-native (npm install mongodb)
8. mongodb (duh)
9. a turntable.fm userid, auth, and roomid (https://github.com/alaingilbert/Turntable-API/wiki/How-to-find-the:-auth,-userid-and-roomid)
10. The fortune (6) command is in your path, and your fortunes database includes a "humorists" section.

Running
=======

encobot assumes you're running mongodb on localhost on the default port.
encobot assumes there is a directory named log into which she can write her log file.

    $ cp defaults.coffee <room>.coffee
    $ # edit room.coffee to taste
    $ coffee ./encobot.coffee  ./<room>.coffee

