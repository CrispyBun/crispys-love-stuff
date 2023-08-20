local utf8 = require("utf8")

---@class TaggedTextChunk
---@field text string The string of this part of the full text
---@field params table A dictionary of all params and their values for this part of the full text

local openingBracketCode = utf8.codepoint("[")
local closingBracketCode = utf8.codepoint("]")
local escapeCharacterCode = utf8.codepoint("\\")
local paramUnsetKeywords = {"none", "unset", "/"}

local function isParamUnsetKeyword(str)
    for i = 1, #paramUnsetKeywords do
        if str == paramUnsetKeywords[i] then return true end
    end
    return false
end

---@param str string
---@return string
local function trim(str)
    return (str:gsub("^%s*(.-)%s*$", "%1"))
end

---@param str string Input string
---@param sep string Single character seperator
---@return string[]
local function split(str, sep)
    local strings = {}
    for match in string.gmatch(str, "([^" .. sep .. "]*)[" .. sep .. "]?") do
        strings[#strings+1] = match
    end
    if string.sub(str, #str, #str) ~= sep then
        strings[#strings] = nil
    end
    return strings
end

---@param t table
---@return table
local function duplicateDictionary(t)
    local newTable = {}
    for key, value in pairs(t) do
        newTable[key] = value
    end
    return newTable
end

---@param t table
---@return table
local function reverseList(t)
    local reversed = {}
    for i = 1, #t do
        reversed[#t+1-i] = t[i]
    end
    return reversed
end

---@param str string
---@return string
local function removeEscapes(str)
    local escapeChar = utf8.char(escapeCharacterCode)
    local escaped = false
    local resultString = {}
    for i = 1, #str do -- I was hoping a simple pattern gsub would work but i cant seem to figure one out
        local char = string.sub(str, i, i)

        if escaped or (char ~= escapeChar) then
            resultString[#resultString+1] = char
        end

        escaped = false
        if char == escapeChar then escaped = true end
    end
    return table.concat(resultString)
end

---@param str string The tag, including the [[ and ]] at the start and end
---@return table params Table of params (as keys) and their values
local function decodeTag(str)
    str = string.sub(str, 3, -3) -- trim off brackets
    str = removeEscapes(str)

    local params = {}

    for param, value in string.gmatch(str, "([^:;]+):([^;]+)") do
        param = trim(param)
        value = trim(value)

        if isParamUnsetKeyword(value) then
            params[param] = false
        else
            params[param] = value
        end
    end

    return params
end

---comment
---@param str string A string with no newlines
---@param params? table What params the string should already have
---@return TaggedTextChunk[] taggedText A table of tables containing the text and params of that part of the string
local function stringToTaggedText(str, params)
    params = params or {}
    local taggedText = {{params = params}}

    local escaped = false
    local codePrevious
    local tagStart
    local stringChunk = {}
    for position, code in utf8.codes(str) do

        if code == openingBracketCode and codePrevious == openingBracketCode and not tagStart then
            tagStart = utf8.offset(str, 0, position-1)

            stringChunk[#stringChunk] = nil
            taggedText[#taggedText].text = table.concat(stringChunk)
            stringChunk = {}
        end

        if not tagStart and ((code ~= escapeCharacterCode) or escaped) then
            stringChunk[#stringChunk+1] = utf8.char(code)
        end

        if code == closingBracketCode and codePrevious == closingBracketCode and tagStart then
            local tag = string.sub(str, tagStart, position)
            local params = decodeTag(tag)

            taggedText[#taggedText+1] = {params = duplicateDictionary(taggedText[#taggedText].params)}
            for param, value in pairs(params) do
                value = value or nil -- Turn falses to nils to remove them from the table entirely
                taggedText[#taggedText].params[param] = value
            end

            tagStart = nil
        end

        codePrevious = not escaped and code
        if code == escapeCharacterCode and not escaped then escaped = true
        else escaped = false end
    end

    taggedText[#taggedText].text = table.concat(stringChunk)
    return taggedText
end

---@param str string
---@return TaggedTextChunk[][] taggedLines
local function stringToTaggedLines(str)
    local strings = split(str, "\n")
    local taggedLines = {}
    local previousParams
    for i = 1, #strings do
        local currentString = strings[i]
        local taggedLine = stringToTaggedText(currentString, previousParams)

        previousParams = taggedLine[#taggedLine].params

        taggedLines[#taggedLines+1] = taggedLine
    end

    for _, line in ipairs(taggedLines) do
        --print("[new line]")
        for _, taggedTextEntry in ipairs(line) do
            print("TEXT: " .. taggedTextEntry.text)
            for param, value in pairs(taggedTextEntry.params) do
                print(param .. " = " .. value)
            end
            print()
        end
    end

    return taggedLines
end

local function trimWordToMaxWidth(str, font, maxWidth)
    local trimmedChars = {}
    while font:getWidth(str) > maxWidth do

        local byteoffset = utf8.offset(str, -1)

        local trimmedStart = string.sub(str, 1, byteoffset - 1)
        local trimmedEnd = string.sub(str, byteoffset)

        if trimmedStart == "" then break end

        str = trimmedStart
        trimmedChars[#trimmedChars+1] = trimmedEnd
    end

    trimmedChars = reverseList(trimmedChars)
    ---@type string|nil
    local trimmedStr = table.concat(trimmedChars)
    if trimmedStr == "" then trimmedStr = nil end

    return str, trimmedStr
end

---@param str string
---@param font love.Font
---@param maxWidth number
local function makeStringKeepMaxWidth(str, font, maxWidth)
    local words = split(str, " ")
    local lines = {}
    local wordIndex = 1
    local lineIndex = 1
    while wordIndex <= #words do
        local word, trimmedPart = trimWordToMaxWidth(words[wordIndex], font, maxWidth)
        if trimmedPart then
            words[wordIndex] = word
            table.insert(words, wordIndex+1, trimmedPart)
        end

        if not lines[lineIndex] then
            lines[lineIndex] = word
        else
            local updatedLine = lines[lineIndex] .. " " .. word
            if font:getWidth(updatedLine) > maxWidth then
                lines[lineIndex + 1] = word
                lineIndex = lineIndex + 1
            else
                lines[lineIndex] = updatedLine
            end
        end

        wordIndex = wordIndex + 1
    end
    return lines
end

local font = love.graphics.newFont(15, "mono")
local lines = makeStringKeepMaxWidth("splitting text into multiple lines to keep a max width :-)", font, 100)
for index, value in ipairs(lines) do
    print(value)
end

local testString = "This is a [[color: highlight]]test[[color: none;]] string.\nYou use \\[[these: tags]] to [[shake:100;color:highlight;]]tag[[color:none]] text[[shake:none]]."
stringToTaggedLines(testString)