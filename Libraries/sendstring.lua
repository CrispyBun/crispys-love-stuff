----------------------------------------------------------------------------------------------------
-- A simple data to string, and string to data encoding library
-- written by yours truly, CrispyBun.
-- crispybun@pm.me
----------------------------------------------------------------------------------------------------
--[[
MIT License

Copyright (c) 2024 Ava "CrispyBun" Špráchalů

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
--]]
----------------------------------------------------------------------------------------------------

--- The sendstring header always contains:
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
--- Example sendstring messages:  
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
local sendstring = {}

--- The separator for data in messages.  
--- Make sure this is a string that can never appear in any of the stringified data. You can change this right before generating a message to change its separator.
---@type string
sendstring.dataSeparator = "\n\n"

--- The character that defines the end of the separator in a message. This string must be a single char and cannot be anywhere in the separator string.
---@type string
sendstring.separatorSeparator = ":"

--- A message identifier and the fields it sends, in order. The last provided field is special, as its value may contain the separator of the message its sent in.
---@type table<string, Sendstring.MessageField[]>
sendstring.messageTypes = {}

--- The defined data types and their parsers. Some are provided out of the box by the library, defined later.
---@type table<string, Sendstring.Parser>
sendstring.dataTypes = {}

--------------------------------------------------
--- Definitions

--- Defines a key in the table of a parsed message, and its data type (as a string which is present in sendstring.dataTypes).
---@class Sendstring.MessageField
---@field key string|number The key this data will be present at in the non-stringified table
---@field dataType string The dataType to use for this field

--- Defines how a type should be converted to and from a string
---@class Sendstring.Parser
---@field stringify fun(value: any): boolean, string Function for converting the value to a string. Must return a success boolean and the converted string (or some default string if unsuccessful).
---@field parse fun(str: string): boolean, any Function for parsing a string back into the value. Must return a success boolean and the converted value (or some default value if unsuccesful).

--------------------------------------------------
--- Parsers

local function undefinedStringify() error("The 'stringify' function for this parser has not been defined", 2) end
local function undefinedParse() error("The 'parse' function for this parser has not been defined", 2) end

--- Creates a new parser. You can pass in the `stringify` and `parse` functions immediately, or set them after creation.
---@param stringify? fun(value: any): boolean, string
---@param parse? fun(str: string): boolean, any
---@return Sendstring.Parser
function sendstring.newParser(stringify, parse)
    ---@type Sendstring.Parser
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
---@param parser Sendstring.Parser The parser of the data type
function sendstring.defineDataType(name, parser)
    sendstring.dataTypes[name] = parser
end

--- Defines a new message type
---@param name string The name of the message type
---@param fields Sendstring.MessageField[] The fields to come with this message. These can either be generated using `sendstring.newMessageField`, or just skip the middleman and add the tables directly.
function sendstring.defineMessageType(name, fields)
    sendstring.messageTypes[name] = fields
end

--- Creates a field to go into `sendstring.messageTypes`
--- 
--- Example usage:
--- ```lua
--- sendstring.defineMessageType("Position", {
---     sendstring.newMessageField("x", "number"),
---     sendstring.newMessageField("y", "number")
--- })
--- ```
---@param key string|number The key this data will be present at in the non-stringified table
---@param dataType string The dataType to use for this field, as defined in `sendstring.dataTypes`
function sendstring.newMessageField(key, dataType)
    ---@type Sendstring.MessageField
    local field = {
        key = key,
        dataType = dataType
    }
    return field
end
sendstring.newField = sendstring.newMessageField

--- Creates a new message (string) from the defined message name and a table of the necessary data (as defined in the message fields)
---@param name string The name of the message as defined in `sendstring.messageTypes`
---@param data table All of the keys and values the message expects, as defined in `sendstring.messageTypes`
---@return string
function sendstring.generateMessage(name, data)
    local fields = sendstring.messageTypes[name]
    if not fields then error("Unknown message: '" .. tostring(name) .. "'", 2) end

    local msgHeader = {
        sendstring.separatorSeparator,
        sendstring.dataSeparator,
        sendstring.separatorSeparator,
        "\n"
    }
    local msgBody = {
        name
    }

    if string.find(name, sendstring.dataSeparator) then error("Message name contains the data separator", 2) end

    for fieldIndex = 1, #fields do
        local field = fields[fieldIndex]

        local parserName = field.dataType
        local parser = sendstring.dataTypes[parserName]
        if not parser then error("Message has undefined dataType '" .. tostring(parserName) .. "'", 2) end

        local key = field.key
        local value = data[key]
        local success, str = parser.stringify(value)

        if fieldIndex < #fields and string.find(str, sendstring.dataSeparator) then error("Value '" .. tostring(key) .. "' contains the data separator after being parsed", 2) end

        if not success then error("Value type '" .. tostring(parserName) .. "' couldn't stringify the supplied value (" .. tostring(value) .. ")", 2) end
        msgBody[#msgBody+1] = str
    end

    return table.concat(msgHeader) .. table.concat(msgBody, sendstring.dataSeparator)
end

--- The same as `sendstring.generateMessage`, but the message name must be provided in the `data` table under the key `_MESSAGETYPE`.
---@param data table
---@return string
function sendstring.generateMessageAuto(data)
    if not data._MESSAGETYPE then error("_MESSAGETYPE not supplied in data", 2) end
    return sendstring.generateMessage(data._MESSAGETYPE, data)
end

--- Attempts to parse the message. Won't error - will either return `true, data` or `false, error`.  
--- This function doesn't need `sendstring.dataSeparator` or `sendstring.separatorSeparator` set - those are provided by the message.  
--- 
--- The resulting table will also have the `_MESSAGETYPE` field containing the name of the message that constructed it (as defined in `sendstring.messageTypes`).
---@param str string
---@return boolean success
---@return table|string dataOrError
function sendstring.parseMessage(str)
    local separatorSeparator = string.sub(str, 1, 1)
    local headerEnd = string.find(str, separatorSeparator, 2, true)
    if not headerEnd then return false, "Malformed header" end

    local separator = string.sub(str, 2, headerEnd-1)
    if string.sub(str, headerEnd+1, headerEnd+1) ~= "\n" then return false, "Malformed header" end

    local messageNameEnd = string.find(str, separator, headerEnd+2, true)
    if not messageNameEnd then
        local rest = string.sub(str, headerEnd+2)

        local messageType = sendstring.messageTypes[rest]
        if messageType and #messageType == 0 then
            return true, { _MESSAGETYPE = rest } -- Message type with no data
        end

        return false, "Missing body"
    end

    local messageName = string.sub(str, headerEnd+2, messageNameEnd-1)
    local fields = sendstring.messageTypes[messageName]
    if not fields then return false, "Unknown message ID" end

    local separatorLength = #separator
    local searchIndex = messageNameEnd + separatorLength

    local parsedData = {
        _MESSAGETYPE = messageName
    }

    for fieldIndex = 1, #fields do
        local field = fields[fieldIndex]

        local parserName = field.dataType
        local parser = sendstring.dataTypes[parserName]
        if not parser then return false, "Message requires unknown data type: " .. tostring(parserName) end

        local dataStart = searchIndex
        local dataEnd
        if fieldIndex == #fields then
            dataEnd = #str
        else
            dataEnd = string.find(str, separator, searchIndex)
            if not dataEnd then return false, "Missing data" end

            searchIndex = dataEnd + separatorLength
            dataEnd = dataEnd - 1
        end

        local dataStr = string.sub(str, dataStart, dataEnd)
        local success, value = parser.parse(dataStr)
        if not success then return false, "Couldn't parse data #" .. fieldIndex end

        local key = field.key
        parsedData[key] = value
    end

    return true, parsedData
end

--------------------------------------------------
--- Out of the box parsers
--- Careful - some of these make certain dataSeparators unusable, such as a comma.

-- Just lets the string through with no parsing, so this can potentially break any dataSeparator.
sendstring.dataTypes.string = sendstring.newParser(
function (value)
    if type(value) ~= "string" then return false, tostring(value) end
    return true, value
end,

function (str)
    return true, str
end)

sendstring.dataTypes.number = sendstring.newParser(
function (value)
    if type(value) ~= "number" then return false, "0" end
    return true, tostring(value)
end,

function (str)
    local num = tonumber(str)
    if not num then return false, 0 end
    return true, num
end)

sendstring.dataTypes["number[]"] = sendstring.newParser(
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

return sendstring