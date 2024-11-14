local enet = require 'enet'

local sucket = {}

--------------------------------------------------
--- Encoding
--- (define these please)
--- (or use netstring.lua)

--- An encoding function for sending messages over the network.  
--- 
--- Takes in any value which should be sent and returns a string of the encoded value, or potentially errors.  
--- 
--- If this isn't supplied, a simple `tostring` will be used.
---@type fun(value: any): string
sucket.encode = nil

--- A decoding function for decoding messages which arrived over the network.  
--- 
--- Takes in the encoded string value, and returns two values: a boolean whether decoding was successful, and the decoded value itself (or potentially an error message string). This function shouldn't error.
--- 
--- If this isn't supplied, arriving messages won't be decoded at all and will simply be kept as strings.
---@type fun(msg: string): boolean, any
sucket.decode = nil

--------------------------------------------------
--- Logging

---@alias sucket.Logger {log: fun(self: table, message: string, level?: string)}

--- If implemented, this will be used to add a logger to all new servers and clients
---@type fun(): sucket.Logger
sucket.createLogger = nil

--------------------------------------------------
--- Definitions

---@class Sucket.Server
---@field host enet.host The enet host of the server
---@field peers table<enet.peer, boolean> The peers connected to the server
---@field logger? sucket.Logger An optional logger object with any implementation
local Server = {}
local ServerMT = {__index = Server}

--------------------------------------------------
--- Server

---@type integer|string
sucket.serverDefaultPort = "12832"

---@type integer
sucket.serverDefaultMaxClients = 64

--- Creates and starts a new server. If for whatever reason the server isn't able to start, this function will return `nil` instead.
---@param localOnly? boolean If true, the server will start configured to only run locally for a single client.
---@param maxClients? integer The maximum allowed number of clients on the server. Default is the value in `sucket.serverDefaultMaxClients`.
---@param port? integer|string The port to launch the server on. Default is `"0"` if `localOnly` is true, or otherwise the value in `sucket.serverDefaultPort`.
---@return Sucket.Server? server
function sucket.newServer(localOnly, maxClients, port)
    local ip = localOnly and "localhost" or "*"
    port = port or (localOnly and "0" or sucket.serverDefaultPort) -- port 0 is a wildcard to find any port
    maxClients = maxClients or (localOnly and 1 or sucket.serverDefaultMaxClients)

    local address = ip .. ":" .. port

    local success, host = pcall(enet.host_create, address, maxClients)
    if not success then return nil end
    if not host then return nil end

    ---@type Sucket.Server
    local server = {
        host = host,
        peers = {},
    }

    if sucket.createLogger then
        local logger = sucket.createLogger()
        logger:log(string.format("Server created at %s", tostring(server.host:get_socket_address())), "info")
        server.logger = logger
    end

    return server
end

return sucket