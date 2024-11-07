local netstring = {}

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