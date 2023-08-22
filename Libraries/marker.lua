local utf8 = require("utf8")

---@class MarkerTaggedTextChunk
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
    if str == "" then return {""} end
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
---@return MarkerTaggedTextChunk[] taggedText A table of tables containing the text and params of that part of the string
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

    if not tagStart then
        taggedText[#taggedText].text = table.concat(stringChunk)
    else
        -- There was a start of a tag but it was never closed, so just treat is as regular text
        local remainingText = string.sub(str, tagStart, -1)
        taggedText[#taggedText].text = taggedText[#taggedText].text .. remainingText
    end
    return taggedText
end

---@param str string
---@return MarkerTaggedTextChunk[][] taggedLines
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
---@param firstLineWidthUsedUp? number How much width has already been taken from the first line (reduce max width by it)
---@return string[] lines
local function makeStringKeepMaxWidth(str, font, maxWidth, firstLineWidthUsedUp)
    firstLineWidthUsedUp = firstLineWidthUsedUp or 0
    local words = split(str, " ")
    local lines = {}
    local wordIndex = 1
    local lineIndex = 1
    while wordIndex <= #words do
        local maxLineWidth = lineIndex == 1 and (maxWidth - firstLineWidthUsedUp) or (maxWidth)

        local word, trimmedPart = trimWordToMaxWidth(words[wordIndex], font, maxWidth)
        if trimmedPart then
            words[wordIndex] = word
            table.insert(words, wordIndex+1, trimmedPart)
        end

        if not lines[lineIndex] then
            if font:getWidth(word) > maxLineWidth then -- This can only happen if firstLineWidthUsedUp makes maxWidth too small
                lines[lineIndex] = ""
                lines[lineIndex + 1] = word
                lineIndex = lineIndex + 1
            else
                lines[lineIndex] = word
            end
        else
            local updatedLine = lines[lineIndex] .. " " .. word
            if font:getWidth(updatedLine) > maxLineWidth then
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

---@param taggedLines MarkerTaggedTextChunk[][]
---@param font love.Font
---@param maxWidth number
local function makeTaggedLinesKeepMaxWidth(taggedLines, font, maxWidth)
    local lineIndex = 1
    while lineIndex <= #taggedLines do
        local line = taggedLines[lineIndex]
        local lineWidthUsedUp = 0

        for chunkIndex = 1, #line do
            local chunk = line[chunkIndex]
            local splitChunkText = makeStringKeepMaxWidth(chunk.text, font, maxWidth, lineWidthUsedUp)

            if #splitChunkText == 1 then -- there is room for more on this line
                lineWidthUsedUp = lineWidthUsedUp + font:getWidth(splitChunkText[1])
            else
                chunk.text = splitChunkText[1] -- trim this chunk to whatever still fits
                for i = 2, #splitChunkText do
                    table.insert(taggedLines, lineIndex+1, {{text = splitChunkText[i], params = chunk.params}})
                    lineIndex = lineIndex + 1
                end

                for remainingChunkIndex = chunkIndex + 1, #line do
                    taggedLines[lineIndex][#taggedLines[lineIndex]+1] = line[remainingChunkIndex]
                    line[remainingChunkIndex] = nil
                end
                if splitChunkText[1] == "" then line[chunkIndex] = nil end

                lineIndex = lineIndex - 1
                break
            end
        end
        lineIndex = lineIndex + 1
    end
    return taggedLines
end

local font = love.graphics.newFont(15, "mono")
local untaggedText = "splitting text into multiple lines to keep a max width :-)"
local taggedText = "[[typewriter:1]]splitting [[color:highlight]]text[[color:none;]] into [[wobble:5]]multiple lines[[wobble:unset]] to keep a max width :-)"
local lines1 = makeStringKeepMaxWidth(untaggedText, font, 100)
for index, value in ipairs(lines1) do
    print(value)
end
print("\n[NEXT]\n")
local lines3 = makeTaggedLinesKeepMaxWidth(stringToTaggedLines(taggedText), font, 100)
for _, line in ipairs(lines3) do
    local str = ""
    for _, chunk in ipairs(line) do
       str = str .. chunk.text
    end
    print(str)
end
print("\n[AND TAGGED:]\n")
for _, line in ipairs(lines3) do
    print()
    print("NEW LINE")
    for _, chunk in ipairs(line) do
       print("TEXT: " .. chunk.text)
       print("PARAMS:")
       for param, value in pairs(chunk.params) do
            print("  " .. param .. " = " .. value)
       end
    end
end

local testString = "This is a [[color: highlight;]]test[[color: none;]] string.\nYou use \\[[these: tags]] to [[shake:100;color:highlight;]]tag[[color:none]] text[[shake:none]]."
--stringToTaggedLines(testString)