local utf8 = require("utf8")

local marker = {}

marker.textColors = {
    default = {1,1,1},
    highlight = {1,0.4,0.3},

    red = {1,0,0},
    green = {0,1,0},
    blue = {0,0,1}
}

local split
local function splitParamValue(value)
    return split(value, ",")
end

local textEffects = {}
---@param effectText {[1]: MarkerEffectTextChunk, [2]: string}[]
function textEffects.color(effectText, time)
    for index = 1, #effectText do
        local chunk = effectText[index][1]
        local paramValue = effectText[index][2]

        local color = marker.textColors[paramValue] or marker.textColors.default
        chunk.color = color
    end
end
---@param effectText {[1]: MarkerEffectTextChunk, [2]: string}[]
function textEffects.shake(effectText, time)
    local seed = 1201
    for index = 1, #effectText do
        local chunk = effectText[index][1]
        local paramValue = effectText[index][2]

        local values = splitParamValue(paramValue)
        local speed = (tonumber(values[1]) or 1)
        local intensity = (tonumber(values[2]) or 1)

        local shakeAmount = math.floor(intensity * 5)
        local speedSeeder = math.floor(time * speed * 25) + seed

        love.math.setRandomSeed(speedSeeder)
        local shakeX = love.math.random() - 0.5
        love.math.setRandomSeed(speedSeeder+1)
        local shakeY = love.math.random() - 0.5

        chunk.xOffset = chunk.xOffset + shakeX * shakeAmount
        chunk.yOffset = chunk.yOffset + shakeY * shakeAmount
    end
end
---@param effectText {[1]: MarkerEffectTextChunk, [2]: string}[]
function textEffects.wiggle(effectText, time)
    for index = 1, #effectText do
        local chunk = effectText[index][1]
        local paramValue = effectText[index][2]

        local values = splitParamValue(paramValue)
        local speed = (tonumber(values[1]) or 1)
        local intensity = (tonumber(values[2]) or 1)
        local timeOffset = (tonumber(values[3]) or 0)

        local offset = math.sin((index * -timeOffset) + time * speed * 10)

        chunk.yOffset = chunk.yOffset + offset * intensity
    end
end

---@class MarkerTaggedTextChunk
---@field text string The string of this part of the full text
---@field params table A dictionary of all params and their values for this part of the full text

---@class MarkedText
---@field rawText string The input string used for the MarkedText
---@field maxWidth number
---@field font love.Font
---@field textChunks string[][] Input string split into chunks in lines
---@field params table<string, table> The params and the addresses of the affected chunks, with the value of the param stored with each address
---@field time number Timer for effects dependant on it
---
---@field x number X position to draw the text at
---@field y number Y position to draw the text at
---@field textAlign string How to align the text horizontally
---@field verticalAlign string How to align the text vertically
---@field alignInBox boolean If true, won't align to the coordinates but according to the max width
---@field boxHeight number The height to use (to be used alongside alignInBox set to true)
---@field update fun(dt: number) Updates the text to be able to have animated effects
---@field draw fun() Draws the text
---@field getHeight fun(): number Gets the full height of the string

---@class MarkerEffectTextChunk
---@field text string The text of the chunk
---@field color number[] The color of the chunk
---@field xOffset number Offset of the chunk on the X axis
---@field yOffset number Offset of the chunk on the Y axis

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
function split(str, sep)
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
---@return boolean chainTagged If this tag is applied to each character individually
local function decodeTag(str)
    str = string.sub(str, 3, -3) -- trim off brackets
    str = removeEscapes(str)

    local chainTagged = false
    if string.sub(str, 1, 1) == "~" then
        str = string.sub(str, 2, -1)
        chainTagged = true
    end

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

    return params, chainTagged
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
    local chainTagged = false
    for position, code in utf8.codes(str) do

        if code == openingBracketCode and codePrevious == openingBracketCode and not tagStart then
            tagStart = utf8.offset(str, 0, position-1)

            if chainTagged then
                taggedText[#taggedText] = nil
            end
            chainTagged = false

            stringChunk[#stringChunk] = nil
            taggedText[#taggedText].text = table.concat(stringChunk)
            stringChunk = {}
        end

        if not tagStart and ((code ~= escapeCharacterCode) or escaped) then
            local char = utf8.char(code)
            stringChunk[#stringChunk+1] = char

            if chainTagged then
                taggedText[#taggedText].text = char
                taggedText[#taggedText+1] = {params = duplicateDictionary(taggedText[#taggedText].params)}
                stringChunk = {}
            end
        end

        if code == closingBracketCode and codePrevious == closingBracketCode and tagStart then
            local tag = string.sub(str, tagStart, position)
            local params
            params, chainTagged = decodeTag(tag)

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

    if str == "" then return "", nil end

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
            local wordWidth = font:getWidth(word)
            if wordWidth > maxLineWidth and firstLineWidthUsedUp > 0 and word ~= "" then -- This can only happen if firstLineWidthUsedUp makes maxWidth too small
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

---@param str string Input string
---@param font love.Font Font used
---@param maxWidth? number Max width for the text to keep
---@return table textChunks
---@return table params
local function stringToStyledTextGuts(str, font, maxWidth)
    maxWidth = maxWidth or math.huge
    local taggedLines = stringToTaggedLines(str)
    taggedLines = makeTaggedLinesKeepMaxWidth(taggedLines, font, maxWidth)

    local textChunks = {}
    local params = {}

    for lineIndex = 1, #taggedLines do
        local line = taggedLines[lineIndex]
        textChunks[lineIndex] = {}
        for chunkIndex = 1, #line do
            local chunk = line[chunkIndex]
            textChunks[lineIndex][chunkIndex] = chunk.text

            for param, value in pairs(chunk.params) do
                local address = {lineIndex,chunkIndex}
                address.value = value
                address.desynced = false -- todo
                if not params[param] then
                    params[param] = {address}
                else
                    params[param][#params[param]+1] = address
                end
            end
        end
    end

    return textChunks, params
end

local verticalAlignEnum = {
    top = -1,
    bottom = 1,
    middle = 0,
    center = 0
}

local function getEffectChunkLineWidth(line, font)
    local width = 0
    for chunkIndex = 1, #line do
        local chunk = line[chunkIndex].text
        width = width + font:getWidth(chunk)
    end
    return width
end

local drawFunctions = {}
function drawFunctions.left(markedText, horizontalAlign)
    local textChunks = markedText.textChunks
    local time = markedText.time
    local font = markedText.font
    local x = markedText.x
    local y = markedText.y

    horizontalAlign = horizontalAlign or -1

    local lineHeight = font:getHeight()

    local fullHeight = markedText.getHeight() - markedText.boxHeight
    local verticalAlign = verticalAlignEnum[markedText.verticalAlign] or -1
    local yOffset = fullHeight / 2 + (fullHeight / 2) * verticalAlign
    y = y - yOffset

    local ignoreAlignInBox = false
    if (markedText.maxWidth == math.huge or markedText.maxWidth < 0) and markedText.alignInBox then
        horizontalAlign = -1
        ignoreAlignInBox = true
    end
    if markedText.alignInBox and not ignoreAlignInBox then
        local halfMaxWidth = markedText.maxWidth / 2
        local xOffset = halfMaxWidth + halfMaxWidth * horizontalAlign
        x = x + xOffset
    end

    -- Prepare table to be passed into effects
    local effectTextChunks = {}
    for lineIndex = 1, #textChunks do
        local line = textChunks[lineIndex]
        effectTextChunks[lineIndex] = {}

        for chunkIndex = 1, #line do
            local text = line[chunkIndex]

            ---@type MarkerEffectTextChunk
            local effectChunk = {
                text = text,
                color = marker.textColors.default,
                xOffset = 0,
                yOffset = 0
            }
            effectTextChunks[lineIndex][chunkIndex] = effectChunk
        end
    end

    -- Run the effects
    for effect, addresses in pairs(markedText.params) do
        if textEffects[effect] then
            local chunks = {}
            for addressIndex = 1, #addresses do
                local address = addresses[addressIndex]
                local lineIndex = address[1]
                local chunkIndex = address[2]
                local value = address.value

                local chunk = effectTextChunks[lineIndex][chunkIndex]
                chunks[#chunks+1] = {chunk, value}
            end
            textEffects[effect](chunks, time)
        end
    end

    local prevColorR, prevColorG, prevColorB, prevColorA = love.graphics.getColor()
    for lineIndex = 1, #effectTextChunks do
        local line = effectTextChunks[lineIndex]
        local halfLineWidth = getEffectChunkLineWidth(line, font) / 2
        local lineOffset = halfLineWidth + halfLineWidth * horizontalAlign

        local drawX = math.floor(x - lineOffset)
        local drawY = math.floor(y + lineHeight * (lineIndex-1))
        for chunkIndex = 1, #line do
            local chunk = line[chunkIndex]
            love.graphics.setColor(chunk.color)
            love.graphics.print(chunk.text, font, drawX + chunk.xOffset, drawY + chunk.yOffset)
            drawX = drawX + font:getWidth(chunk.text)
        end
    end
    love.graphics.setColor(prevColorR, prevColorG, prevColorB, prevColorA)
end
function drawFunctions.right(markedText)
    return drawFunctions.left(markedText, 1)
end
function drawFunctions.center(markedText)
    return drawFunctions.left(markedText, 0)
end
function drawFunctions.middle(markedText)
    return drawFunctions.center(markedText)
end

---@param str? string String used for the text
---@param font? love.Font Font used for the text
---@param maxWidth? number Max width for the text to keep (Default is no max width)
---@param x? number X position of the text (Default is 0)
---@param y? number Y position of the text (Default is 0)
---@param textAlign? string How to align the text horizontally ("left", "right", "center") (Default is left)
---@param verticalAlign? string How to align the text vertically ("top", "bottom", "middle")
---@param alignInBox? boolean If true, won't align to the X coordinate but according to the max width
---@return MarkedText
function marker.newMarkedText(str, font, maxWidth, x, y, textAlign, verticalAlign, alignInBox)
    str = str or ""
    font = font or love.graphics.newFont(15, "mono")
    maxWidth = maxWidth or math.huge
    x = x or 0
    y = y or 0
    textAlign = textAlign or "left"
    verticalAlign = verticalAlign or "top"
    alignInBox = alignInBox or false

    local textChunks, params = stringToStyledTextGuts(str, font, maxWidth)

    local markedText = {}
    markedText.rawText = str
    markedText.font = font
    markedText.maxWidth = maxWidth
    markedText.textChunks = textChunks
    markedText.params = params
    markedText.x = x
    markedText.y = y
    markedText.textAlign = textAlign
    markedText.verticalAlign = verticalAlign
    markedText.alignInBox = alignInBox
    markedText.boxHeight = 0

    markedText.time = 0

    markedText.getHeight = function ()
        local lineHeight = markedText.font:getHeight()
        return #markedText.textChunks * lineHeight
    end

    markedText.update = function (dt)
        markedText.time = markedText.time + dt
    end

    markedText.draw = function ()
        if drawFunctions[markedText.textAlign] then
            drawFunctions[markedText.textAlign](markedText)
        end
    end

    return markedText
end

-- local font = love.graphics.newFont(15, "mono")
-- local untaggedText = "splitting text into multiple lines to keep a max width :-)"
-- local taggedText = "[[typewriter:1]]splitting [[color:highlight]]text[[color:none;]] into [[wobble:5]]multiple lines[[wobble:unset]] to keep a max width :-)"
-- local lines1 = makeStringKeepMaxWidth(untaggedText, font, 100)
-- for index, value in ipairs(lines1) do
--     print(value)
-- end
-- print("\n[NEXT]\n")
-- local markedText = marker.newMarkedText(taggedText, font, 100)

-- for _, line in ipairs(markedText.textChunks) do
--     local lineStr = ""
--     for chunkIndex, chunk in ipairs(line) do
--         lineStr = lineStr .. chunkIndex .. chunk
--     end
--     print(lineStr)
-- end

-- print("\n[AND TAGS]\n")

-- for key, addresses in pairs(markedText.params) do
--     print(key)
--     for _, address in ipairs(addresses) do
--         print("[" .. address[1] .. ", " .. address[2] .. "]: " .. address.value)
--     end
--     print()
-- end

local testString = "This is a [[color: highlight;]]test[[color: none;]] string.\nYou use \\[[these: tags]] to [[shake:100;color:highlight;]]tag[[color:none]] text[[shake:none]]."

return marker