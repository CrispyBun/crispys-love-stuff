local enet = require 'enet'

local sucket = {}

--------------------------------------------------
--- Defaults

---@type integer|string
sucket.serverDefaultPort = "12832"

---@type integer
sucket.serverDefaultMaxClients = 64

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

---@alias sucket.LogLevel
---| '"none"' # No level assigned
---| '"trace"' # Verbose step by step debug information
---| '"debug"' # Debug information
---| '"info"' # Informative
---| '"warn"' # Unexpected event
---| '"error"' # Problem occured
---| '"fatal"' # Uh oh

---@alias sucket.Logger {log: fun(self: table, message: string, level?: sucket.LogLevel)}

--- If implemented, this will be used to add a logger to all new servers.
---@type fun(): sucket.Logger
sucket.createLogger = nil

--------------------------------------------------
--- Peer objects

--- Inject your own fields into this class.  
--- This class is used to hold anything you need to associate with a connected peer, such as a username or an ID of the player object they control.
---@class Sucket.PeerInfo
---@field enetPeer? enet.peer The actual enet peer, the library uses this field to communicate back to it. It will be populated automatically by the library.

--- You may use this to implement a constructor for `PeerInfo` objects.  
--- If not implemented, a simple empty table will be created for each new `PeerInfo`.
---@type fun(): Sucket.PeerInfo
sucket.createPeerInfo = nil

--------------------------------------------------
--- Definitions

--- An ENet server.
---@class Sucket.Server
---@field host enet.host The enet host of the server
---@field peers table<enet.peer, Sucket.PeerInfo> The peers connected to the server
---@field logger? sucket.Logger An optional logger object with any implementation
local Server = {}
local ServerMT = {__index = Server}

--- An ENet client. Must be connected to a server using `client:connect()` to make it usable.
---@class Sucket.Client
---@field host enet.host The enet host of the client
---@field serverPeer? enet.peer The connection to the server
local Client = {}
local ClientMT = {__index = Client}

--------------------------------------------------
--- Misc

--- Splits an address into an IP and port.  
--- Will return `nil` for the port if it's not there.
function sucket.splitAddress(address)
    local _, colonCount = string.gsub(address, ":", "")
    if colonCount > 1 then
        -- IPv6
        -- ENet doesn't actually support IPv6 but might as well take it into account anyway
        if not string.find(address, "[", 1, true) then return "[" .. address .. "]", nil end
        local ip, port = string.match(address, "%[(.*)%]:(.*)")
        if not port then return address, nil end -- No port
        return ip, port
    end

    local ip, port = string.match(address, "(.*):(.*)")
    if not port then return address, nil end -- No port
    return ip, port
end

--------------------------------------------------
--- Server

--- Creates and starts a new server. If for whatever reason the server isn't able to start, this function will return `nil` instead.
---@param ip? string The address to launch the server on. Can also be `localhost` for a local server or `*` for all interfaces. Defaults to `localhost`.
---@param port? integer|string The port to launch the server on. `"0"` is a wildcard which will find the first available port. Defaults to `sucket.serverDefaultPort`.
---@param maxClients? integer The maximum allowed number of clients on the server. Defaults to `sucket.serverDefaultMaxClients`.
---@return Sucket.Server? server
function sucket.newServer(ip, port, maxClients)
    ip = ip or "localhost"
    port = port or sucket.serverDefaultPort
    maxClients = maxClients or sucket.serverDefaultMaxClients

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

    return setmetatable(server, ServerMT)
end

--- Returns the address the server is running on.
---@return string
function Server:getAddress()
    return self.host:get_socket_address()
end

--- Returns the port the server is running on.
---@return string
function Server:getPort()
    local address = self.host:get_socket_address()
    local port = string.match(address, ".*:(.*)")
    return port
end

-- Processes everything that arrived since the last call to `service`.  
-- Either call this from an update loop or forever in a separate thread.
function Server:service()
    local host = self.host
    local peers = self.peers
    local logger = self.logger

    local success, event = pcall(host.service, host)
    if not success then return end -- It seems service may just not work sometimes in weird edge cases (such as an invalid packet arriving, i believe)

    while event do
        local eventType = event.type
        local eventData = event.data
        local eventPeer = event.peer

        if eventType == "connect" then
            if logger then logger:log(string.format("Established connection: %s", tostring(eventPeer)), "info") end

            local peerInfo = sucket.createPeerInfo and sucket.createPeerInfo() or {}
            peerInfo.enetPeer = eventPeer
            peers[eventPeer] = peerInfo

        elseif eventType == "disconnect" then
            if logger then logger:log(string.format("Disconnected: %s", tostring(eventPeer)), "info") end
            peers[eventPeer] = nil

        elseif eventType == "receive" then
            if logger then logger:log(string.format("Received message from %s", tostring(eventPeer)), "trace") end

            -- todo: process the data here
        else

            -- Shouldn't be possible that this code is ever ran,
            -- but might as well put a log for it, just in case.
            -- A "NONE" event type *does* exist in ENet, but I don't think it should be possible that it sends.
            if logger then logger:log(string.format("Received invalid network event type: '%s' from peer %s", tostring(eventType), tostring(eventPeer)), "error") end
        end

        success, event = pcall(host.service, host)
        if not success then return end
    end
end

--- Sends any queued packets. Useful if `service` won't be called again.
function Server:flush()
    self.host:flush()
end

--------------------------------------------------
--- Client

--- Creates a new client.
function sucket.newClient()
    ---@type Sucket.Client
    local client = {
        host = enet.host_create()
    }
    return setmetatable(client, ClientMT)
end

--- Attempts to connect the client to a server. The connection won't take place until both the server and client run `service`.  
--- 
--- If the server doesn't exist or is unreachable, the client will simply never connect and the state will remain as "connecting".
--- To cancel the connection attempt, call `client:disconnect()` (or perhaps better, `client:disconnectNow()`).
--- 
--- If the connection attempt fails altogether, this function will return `false` and an error message.
---@param ip string The IP of the server.
---@param port? string|number The port of the server. Defaults to `sucket.serverDefaultPort`.
---@return boolean success
---@return string? err
function Client:connect(ip, port)
    port = port or sucket.serverDefaultPort
    local address = ip .. ":" .. port
    local success, serverPeerOrError = pcall(self.host.connect, self.host, address)
    ---@diagnostic disable-next-line: return-type-mismatch
    if not success then return false, serverPeerOrError end

    self.serverPeer = serverPeerOrError
    return true
end

--- Like `Client:connect()`, but will block for the specified timeout waiting for the connection to happen
--- and will cancel the connecton attempt if the timeout is reached.  
--- Has a slight risk of voiding messages if they come in just as the connection is made.  
---@param ip string The IP of the server.
---@param port? string|number The port of the server. Defaults to `sucket.serverDefaultPort`.
---@param timeout? number The maximum number of seconds to wait for the connection to be made. Defaults to `5`.
---@return boolean success
---@return string? err
function Client:connectNow(ip, port, timeout)
    local address = ip .. ":" .. port
    local success, serverPeerOrError = pcall(self.host.connect, self.host, address)
    ---@diagnostic disable-next-line: return-type-mismatch
    if not success then return false, serverPeerOrError end

    local serverPeer = serverPeerOrError

    timeout = timeout or 5
    local startTime = os.clock()
    local endTime = startTime
    while endTime - startTime < timeout do
        local event = self.host:service()

        if serverPeer:state() == "connected" then
            self.serverPeer = serverPeer
            return true
        end

        endTime = os.clock()
    end

    serverPeer:disconnect_now()
    return false, "Connection timed out"
end

--- Requests a disconnection from the server. The request is sent on the next call to `service` or `flush`.
function Client:disconnect()
    if not self.serverPeer then error("Client isn't connected to a server", 2) end
    self.serverPeer:disconnect()
    self.serverPeer = nil
end

--- Forces a disconnection from the server.
--- The server is not guaranteed to be notified of the disconnection, and no disconnect event will be generated.
function Client:disconnectNow()
    if not self.serverPeer then error("Client isn't connected to a server", 2) end
    self.serverPeer:disconnect_now()
    self.serverPeer = nil
end

--- Requests a disconnection from the server, but only after all queued outgoing packets are sent.
function Client:disconnectLater()
    if not self.serverPeer then error("Client isn't connected to a server", 2) end
    self.serverPeer:disconnect_later()
    self.serverPeer = nil
end

---@return boolean
function Client:isConnected()
    if not self.serverPeer then return false end
    return self.serverPeer:state() == "connected"
end

--- Sends (or attempts to send) a message to the server.  
--- Returns `true` if the message was sent successfully.
---@param message string
---@param flag? "reliable"|"unsequenced"|"unreliable"
---@return boolean success
function Client:send(message, flag)
    if not self.serverPeer then return false end
    local status = self.serverPeer:send(message, 0, flag)
    return status == 0
end

--- Processes everything that arrived since the last call to `service`.  
--- Either call this from an update loop or forever in a separate thread.
function Client:service()
    local host = self.host

    local success, event = pcall(host.service, host)
    if not success then return end -- If the client isn't connected anywhere, service just straight up errors

    while event do
        local eventType = event.type
        local eventData = event.data
        local eventPeer = event.peer

        if eventType == "connect" then


        elseif eventType == "disconnect" then


        elseif eventType == "receive" then


        end

        success, event = pcall(host.service, host)
        if not success then return end
    end
end

--- Sends any queued packets. Useful if `service` won't be called again.
function Client:flush()
    self.host:flush()
end

--------------------------------------------------

return sucket