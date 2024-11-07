
--- The netstring header always contains:
--- * `separatorSeparator` symbol
--- * `separator` string
--- * `separatorSeparator` symbol
--- * newline (\n)
--- 
--- After the header, the body contains:
--- * `messageID` (aka messageName)
--- * `separator`
--- * `data1`
--- * `separator`
--- * `data2`
--- * `separator`
--- * ...
--- * `dataN` (The message type defines how many pieces of data should arrive)
--- 
--- `data` or `messageID` cannot contain the separator.
--- The exception is the last piece of data, which may contain anything, including the separator.  
--- 
--- Example netstring messages:  
--- 
--- 'Position' expects 2 number values
--- (here, it receives 100, 100)
--- ```txt
--- :
--- 
--- :
--- Position
--- 
--- 100
--- 
--- 100
--- ```  
--- '3Strings' expects 3 string values
--- (here, it receives "Hi", "Did you know", "THEENDISNEARTHEENDISNEAR")
--- ```txt
--- :END:
--- 3StringsENDHiENDDid you knowENDTHEENDISNEARTHEENDISNEAR
--- ```
local netstring = {}

--- The separator for data in messages.  
--- Make sure this is a string that can never appear in any of the stringified data. You can change this right before generating a message to change its separator.
---@type string
netstring.dataSeparator = "\n\n"

--- The string that defines the end of the separator in a message. This string must be a single char and cannot be anywhere in the separator.
---@type string
netstring.separatorSeparator = ":"

--- A message type identifier and the data types it comes with, in order.
---@type table<string, string[]>
netstring.messageTypes = {}

--- The defined data types and their parsers. Some are provided out of the box by the library, defined later.
---@type table<string, Netstring.Parser>
netstring.dataTypes = {}

--------------------------------------------------
--- Definitions

--- Defines how some type should be converted to and from a string
---@class Netstring.Parser
---@field stringify fun(value: any): boolean, string Function for converting the value to a string. Must return a success boolean and the converted string (or some default string if unsuccessful).
---@field parse fun(str: string): boolean, any Function for parsing a string back into the value. Must return a success boolean and the converted value (or some default value if unsuccesful).

--------------------------------------------------
--- Parsers

local function undefinedStringify() error("The 'stringify' function for this parser has not been defined", 2) end
local function undefinedParse() error("The 'parse' function for this parser has not been defined", 2) end

--- Creates a new parser. You can pass in the `stringify` and `parse` functions immediately, or set them after creation.
---@param stringify? fun(value: any): boolean, string
---@param parse? fun(str: string): boolean, any
---@return Netstring.Parser
function netstring.newParser(stringify, parse)
    ---@type Netstring.Parser
    local parser = {
        stringify = stringify or undefinedStringify,
        parse = parse or undefinedParse
    }
    return parser
end

--------------------------------------------------
--- Message creation and the like

--- Defines a new data type
---@param name string The name of the data type
---@param parser Netstring.Parser The parser of the data type
function netstring.defineDataType(name, parser)
    netstring.dataTypes[name] = parser
end

--- Defines a new message type
---@param name string The name of the message type
---@param types string[] The names of the data types to come with this message, as defined in `netstring.dataTypes`
function netstring.defineMessageType(name, types)
    netstring.messageTypes[name] = types
end

--- Creates a new message (string) from the defined message and data types
---@param name string The name of the message as defined in `netstring.messageTypes`
---@param ... unknown Each of the values the message expects, as defined in `netstring.messageTypes`
function netstring.generateMessage(name, ...)
    local parsers = netstring.messageTypes[name]
    if not parsers then error("Unknown message: '" .. tostring(name) .. "'", 2) end

    local msgHeader = {
        netstring.separatorSeparator,
        netstring.dataSeparator,
        netstring.separatorSeparator,
        "\n"
    }
    local msgBody = {
        name
    }

    for argIndex = 1, #parsers do
        local parserName = parsers[argIndex]
        local parser = netstring.dataTypes[parserName]
        if not parser then error("Message has undefined parser '" .. tostring(parserName) .. "'", 2) end

        local value = select(argIndex, ...)
        local success, str = parser.stringify(value)

        if not success then error("Value type '" .. tostring(parserName) .. "' couldn't stringify the supplied value (" .. tostring(value) .. ")", 2) end
        msgBody[#msgBody+1] = str
    end

    return table.concat(msgHeader) .. table.concat(msgBody, netstring.dataSeparator)
end

--------------------------------------------------
--- Out of the box parsers

netstring.dataTypes.string = netstring.newParser(
function (value)
    if type(value) ~= "string" then return false, tostring(value) end
    return true, value
end,

function (str)
    return true, str
end)

netstring.dataTypes.number = netstring.newParser(
function (value)
    if type(value) ~= "number" then return false, "0" end
    return true, tostring(value)
end,

function (str)
    local num = tonumber(str)
    if not num then return false, 0 end
    return true, num
end)

netstring.dataTypes["number[]"] = netstring.newParser(
function (value)
    if type(value) ~= "table" then return false, "" end
    return true, table.concat(value, ",")
end,

function (str)
    local nums = {}
    local searchIndex = 1
    while true do
        local nextCommaIndex = string.find(str, ",", searchIndex, true)
        local nextNum = string.sub(str, searchIndex, (nextCommaIndex or (#str+1)) - 1)

        local num = tonumber(nextNum)
        if not num then return false, {} end
        nums[#nums+1] = num

        if not nextCommaIndex then break end
        searchIndex = nextCommaIndex + 1
    end
    return true, nums
end)

--------------------------------------------------

return netstring