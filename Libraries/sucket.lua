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

--- To actually retrieve and use the decoded data from incoming messages,
--- add a `callbacks.receive` function to the receiving server or client.

--- An encoding function for sending messages over the network.  
--- 
--- Takes in any value which should be sent and returns a string of the encoded value.  
--- 
--- If this isn't supplied, a simple `tostring` will be used.
---@type fun(value: any): string
sucket.encode = nil

--- A decoding function for decoding messages which arrived from over the network.  
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
---@field enetPeer? enet.peer The actual enet peer, the library uses this field to communicate back to it. It will be populated automatically by the library. You shouldn't touch it yourself.

--- You may use this to implement a constructor for `PeerInfo` objects.  
--- If not implemented, a simple empty table will be created for each new `PeerInfo`.
---@type fun(): Sucket.PeerInfo
sucket.createPeerInfo = nil

--------------------------------------------------
--- Definitions

--- An ENet server.
---@class Sucket.Server
---@field callbacks Sucket.NetworkCallbacks A table of callbacks for network events
---@field host enet.host The enet host of the server
---@field peers table<enet.peer, Sucket.PeerInfo> The peers connected to the server
---@field logger? sucket.Logger An optional logger object with any implementation
local Server = {}
local ServerMT = {__index = Server}

--- An ENet client. Must be connected to a server using `client:connect()` to make it usable.
---@class Sucket.Client
---@field callbacks Sucket.NetworkCallbacks A table of callbacks for network events
---@field host enet.host The enet host of the client
---@field serverPeer? enet.peer The connection to the server
---@field serverPeerInfo? Sucket.PeerInfo
local Client = {}
local ClientMT = {__index = Client}

--- A table of callbacks for various network events.  
--- This table is present in both the `Server` and `Client` classes,
--- and are the easiest way to manage things like processing received messages.
---@class Sucket.NetworkCallbacks
---@field connect? fun(self: Sucket.Server|Sucket.Client, peerInfo: Sucket.PeerInfo) Called when a peer connects.
---@field disconnect? fun(self: Sucket.Server|Sucket.Client, peerInfo: Sucket.PeerInfo) Called when a peer disconnects.
---@field receive? fun(self: Sucket.Server|Sucket.Client, peerInfo: Sucket.PeerInfo, message: any) Called when a message is received.
---@field receiveInvalidData? fun(self: Sucket.Server|Sucket.Client, peerInfo: Sucket.PeerInfo, receivedRaw: string, err: string) Called when invalid data is received (decoder couldn't decode).

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
        callbacks = {}
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

            if self.callbacks.connect then
                self.callbacks.connect(self, peerInfo)
            end

        elseif eventType == "disconnect" then
            if logger then logger:log(string.format("Disconnected: %s", tostring(eventPeer)), "info") end

            if self.callbacks.disconnect then
                self.callbacks.disconnect(self, peers[eventPeer])
            end

            peers[eventPeer] = nil

        elseif eventType == "receive" then
            local message = tostring(eventData)
            local decodedSuccessfully = true

            local decoder = sucket.decode
            if decoder then
                decodedSuccessfully, message = decoder(message)
            end

            if decodedSuccessfully then
                if logger then logger:log(string.format("Received message from %s", tostring(eventPeer)), "trace") end
                if self.callbacks.receive then
                    self.callbacks.receive(self, peers[eventPeer], message)
                end
            else
                if logger then logger:log(string.format("Received invalid data from %s (%s)", tostring(eventPeer), message), "warn") end
                if self.callbacks.receiveInvalidData then
                    self.callbacks.receiveInvalidData(self, peers[eventPeer], tostring(eventData), message)
                end
            end

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

--- Returns a list of all connected peers in no particular order.
---@return Sucket.PeerInfo[]
function Server:getConnectedPeers()
    local peerInfos = {}

    local peerCount = self.host:peer_count()
    for peerIndex = 1, peerCount do
        local peer = self.host:get_peer(peerIndex)
        if peer:state() == "connected" then
            peerInfos[#peerInfos+1] = self.peers[peer]
        end
    end

    return peerInfos
end

--- Tells the peer to disconnect. The request is sent on the next call to `service` or `flush`.
---@param peerInfo Sucket.PeerInfo
function Server:disconnectPeer(peerInfo)
    local peer = peerInfo.enetPeer
    if not peer then error("PeerInfo doesn't contain an ENet peer", 2) end
    peer:disconnect()
end

--- Forces the peer to disconnect. The peer is not guaranteed to be notified of the disconnection.
---@param peerInfo Sucket.PeerInfo
function Server:disconnectPeerNow(peerInfo)
    local peer = peerInfo.enetPeer
    if not peer then error("PeerInfo doesn't contain an ENet peer", 2) end
    peer:disconnect_now()

    if self.callbacks.disconnect then self.callbacks.disconnect(self, peerInfo) end
    self.peers[peer] = nil
end
Server.kick = Server.disconnectPeerNow

--- Tells the peer to disconnect, but only after all queued outgoing packets are sent.
---@param peerInfo Sucket.PeerInfo
function Server:disconnectPeerLater(peerInfo)
    local peer = peerInfo.enetPeer
    if not peer then error("PeerInfo doesn't contain an ENet peer", 2) end
    peer:disconnect_later()
end

--- Forcefully disconnects the peer. The peer is not notified of the disconnection.
---@param peerInfo Sucket.PeerInfo
function Server:forceDisconnectPeer(peerInfo)
    local peer = peerInfo.enetPeer
    if not peer then error("PeerInfo doesn't contain an ENet peer", 2) end
    peer:reset()

    if self.callbacks.disconnect then self.callbacks.disconnect(self, peerInfo) end
    self.peers[peer] = nil
end
Server.forceKick = Server.forceDisconnectPeer

--- Sets the bandwidth limits of the server in bytes/sec. Set to `0` for unlimited.
---@param incoming integer
---@param outgoing integer
function Server:setBandwidthLimit(incoming, outgoing)
    self.host:bandwidth_limit(incoming, outgoing)
end

--------------------------------------------------
--- Client

--- Creates a new client.
function sucket.newClient()
    ---@type Sucket.Client
    local client = {
        host = enet.host_create(),
        callbacks = {}
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

    local peerInfo = sucket.createPeerInfo and sucket.createPeerInfo() or {}
    peerInfo.enetPeer = serverPeerOrError

    self.serverPeer = serverPeerOrError
    self.serverPeerInfo = peerInfo
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
            local peerInfo = sucket.createPeerInfo and sucket.createPeerInfo() or {}
            peerInfo.enetPeer = serverPeer

            self.serverPeer = serverPeer
            self.serverPeerInfo = peerInfo

            if self.callbacks.connect then self.callbacks.connect(self, peerInfo) end
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

    if self.callbacks.disconnect then self.callbacks.disconnect(self, self.serverPeerInfo) end
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
---@param message any The data to send (will be encoded using `sucket.encode`).
---@param flag? "reliable"|"unsequenced"|"unreliable"
---@return boolean success
function Client:send(message, flag)
    local encoder = sucket.encode or tostring
    message = encoder(message)

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

        local peerInfo = self.serverPeerInfo
        if peerInfo and peerInfo.enetPeer ~= eventPeer then
            -- Event isn't from the server we're connected to,
            -- could potentially happen as a super rare edge-case message
            -- from a server we were just connected to but aren't anymore.
            return
        end

        if eventType == "connect" then
            if not peerInfo then error("A connection happened without serverPeerInfo being assigned, which should be impossible", 2) end
            if self.callbacks.connect then self.callbacks.connect(self, peerInfo) end

        elseif eventType == "disconnect" then
            if not peerInfo then error("A disconnection happened without serverPeerInfo being assigned, which should be impossible", 2) end
            if self.callbacks.disconnect then self.callbacks.disconnect(self, peerInfo) end

        elseif eventType == "receive" then
            if not peerInfo then error("A message was received without serverPeerInfo being assigned, which should be impossible", 2) end

            local message = tostring(eventData)
            local decodedSuccessfully = true

            local decoder = sucket.decode
            if decoder then
                decodedSuccessfully, message = decoder(message)
            end

            if decodedSuccessfully then
                if self.callbacks.receive then
                    self.callbacks.receive(self, peerInfo, message)
                end
            else
                if self.callbacks.receiveInvalidData then
                    self.callbacks.receiveInvalidData(self, peerInfo, tostring(eventData), message)
                end
            end

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