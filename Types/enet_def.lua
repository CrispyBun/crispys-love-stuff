---@meta
--- Definition file for enet (incomplete)
--- Transcribed from: https://leafo.net/lua-enet/

---@alias enet.peer_state
---| '"disconnected"'
---| '"connecting"'
---| '"acknowledging_connect"'
---| '"connection_pending"'
---| '"connection_succeeded"'
---| '"connected"'
---| '"disconnect_later"'
---| '"disconnecting"'
---| '"acknowledging_disconnect"'
---| '"zombie"'
---| '"unknown"'

---@alias enet.event_type
---| '"receive"'
---| '"disconnect"'
---| '"connect"'

local enet = {}

-------------------------------------------------

---@class enet.host
enet.host = {}

--- Connects a host to a remote host. Returns peer object associated with remote host. The actual connection will not take place until the next `host:service` is done, in which a `"connect"` event will be generated.
--- 
--- `channel_count` is the number of channels to allocate. It should be the same as the channel count on the server. Defaults to `1`.
--- 
--- `data` is an integer value that can be associated with the connect event. Defaults to `0`.
---@param address string
---@param channel_count? integer
---@param data? integer
---@return enet.peer peer
function enet.host:connect(address, channel_count, data) end

--- Wait for events, send and receive any ready packets. `timeout` is the max number of milliseconds to be waited for an event. By default `timeout` is `0`. Returns `nil` on timeout if no events occurred.
--- 
--- If an event happens, an event table is returned. All events have a `type` entry, which is one of `"connect"`, `"disconnect"`, or `"receive"`. Events also have a `peer` entry which holds the peer object of who triggered the event.
--- 
--- A `"receive"` event also has a `data` entry which is a Lua string containing the data received.
---@param timeout? number
---@return enet.event event
function enet.host:service(timeout) end

--- Returns a string that describes the socket address of the given host. The string is formatted as “a.b.c.d:port”, where “a.b.c.d” is the ip address of the used socket.
---@return string address
function enet.host:get_socket_address() end

-------------------------------------------------

---@class enet.peer
enet.peer = {}

--- Queues a packet to be sent to peer. `data` is the contents of the packet, it must be a Lua string.
--- 
--- `channel` is the channel to send the packet on. Defaults to `0`.
--- 
--- `flag` is one of `"reliable"`, `"unsequenced"`, or `"unreliable"`. Reliable packets are guaranteed to arrive, and arrive in the order in which they are sent. Unsequenced packets are unreliable and have no guarantee on the order they arrive. Defaults to reliable.
---@param data string
---@param channel? integer
---@param flag? "reliable"|"unsequenced"|"unreliable"
function enet.peer:send(data, channel, flag) end

--- Returns the state of the peer as a string. This can be any of the following:
--- * `"disconnected"`
--- * `"connecting"`
--- * `"acknowledging_connect"`
--- * `"connection_pending"`
--- * `"connection_succeeded"`
--- * `"connected"`
--- * `"disconnect_later"`
--- * `"disconnecting"`
--- * `"acknowledging_disconnect"`
--- * `"zombie"`
--- * `"unknown"`
---@return enet.peer_state state
function enet.peer:state() end

-------------------------------------------------

---@class enet.event
---@field type enet.event_type
---@field peer enet.peer
---@field data? string|number
---@field channel? integer