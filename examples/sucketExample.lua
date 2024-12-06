-- Basic sucket + sendstring example

---------------------------------------------

local sucket = require 'libraries.sucket'
local sendstring = require 'libraries.sendstring'

---------------------------------------------

-- Fields in messageTypes can either be defined directly with tables like this:
sendstring.defineMessageType("ChatMessage", {
    {
        key = "text",
        dataType = "string" -- ("string" is a built-in dataType. You can define your own.)
    },
})

-- Or using `sendstring.newMessageField` like this:
sendstring.defineMessageType("SetUsername", {
    sendstring.newMessageField("username", "string"),

    -- A message type can have as many fields as you want:
    -- sendstring.newMessageField("color", "number"),
    -- sendstring.newMessageField("fontSize", "number"),
    -- ...
})

---------------------------------------------

-- Let sucket know how to encode and decode messages (using sendstring in our case)
sucket.encode = sendstring.generateMessageAuto
sucket.decode = sendstring.parseMessage

---------------------------------------------

-- Basic printing logger for sucket servers
sucket.createLogger = function ()
    return {
        log = function (self, message, level)
             -- "trace" is a bit too verbose (triggers upon the server receiving a message),
             -- so let's ignore it
            if level == "trace" then return end

            print(level, ":", message)
        end
    }
end

---------------------------------------------

-- Custom data to be associated with network peers

---@class Sucket.PeerInfo
---@field username string

sucket.createPeerInfo = function ()
    return {
        username = "Unnamed User"
    }
end

---------------------------------------------

-- If no arguments are provided, servers are created on "localhost" with the port in `sucket.serverDefaultPort`.
-- Same for clients and the address they connect to.

local server = sucket.newServer()
local client = sucket.newClient()

if not server then error("Invalid server configuration") end

client:connect()

---------------------------------------------

function love.update(dt)
    -- Call service on both server and client regularly,
    -- either in some update loop or continuously in a separate thread
    server:service()
    client:service()
end

-- Click to set username, press any key to send a message:

function love.mousepressed()
    local message = {
        username = "fish",

        _MESSAGETYPE = "SetUsername" -- Define the message type directly in the table that's being sent
    }

    client:send(message)
end

function love.keypressed()
    local message = {
        text = "Hello, World!",
        -- color = 0xff0000, -- Once again, more than 1 field is supported, of course

        _MESSAGETYPE = "ChatMessage",
    }

    client:send(message)
end

---------------------------------------------

-- The `receive` callback gets the parsed data (in our case with sendstring, always a table) as the `message` argument
server.callbacks.receive = function (owner, peerInfo, message)
    -- Print messages
    if message._MESSAGETYPE == "ChatMessage" then
        print(string.format("%s says: %s", peerInfo.username, message.text))
    end

    -- Set usernames
    if message._MESSAGETYPE == "SetUsername" then
        peerInfo.username = message.username
    end
end