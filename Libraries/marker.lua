local utf8 = require("utf8")

local marker = {}

marker.colors = {
    default = {1, 1, 1}, -- A "default" should always exist
    red = {1, 0.1, 0.15},
    green = {0, 1, 0.1},
    blue = {0.2, 0.2, 1},
}

--- Arbitrary callbacks triggered by some events from marker texts, you can add functions listening to them into this table
---@type table<string, fun(data: {charTable?: Marker.ParamCharCollapsed})>
marker.callbacks = {}

-- Defined callbacks are:
-- 'typewriter' (triggers on each new character written by the typewriter text effect)

local paramUnsetKeywords = {"none", "unset", "/"}

----------------------------------------------------------------------------------------------------
-- Class definitions ------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------

---@class Marker.ParamDictionary
---@field [string] string|false

---@class Marker.ParamChar
---@field text string The string this character represents. Usually one character, but can actually be more, however, it will still act as one character and won't be able to be split.
---@field params Marker.ParamDictionary The parameters and their values for this char

---@alias Marker.TextAlign
---| '"default' # A default alignment. Identical to "left" (but you should use "left" instead of "default")
---| '"left"' # Aligns text to the left horizontally
---| '"right"' # Aligns text to the right horizontally
---| '"center"' # Aligns text to the center horizontally
---| '"middle"' # Identical to "center"

---@alias Marker.VerticalAlign
---| '"top"' # Aligns to top (This is the default)
---| '"middle"' # Aligns to the middle
---| '"center"' # Identical to "middle"
---| '"bottom"' # Aligns to bottom

---@class Marker.MarkedText
---@field x number The X location to draw the text at
---@field y number The Y location to draw the text at
---@field font love.Font The font used for drawing the text
---@field maxWidth number The maximum width the text can take up
---@field time number The accumulated elapsed deltatime
---@field timePrevious number The time value at the time of the previous update
---@field textAlign Marker.TextAlign
---@field verticalAlign Marker.VerticalAlign
---@field boxHeight number
---@field doRelativeXAlign boolean
---
---@field rawString string The string used in creation of this markedText, with no processing
---@field strippedString string The raw string stripped of its tags, leaving only plaintext
---@field paramString Marker.ParamChar[] The full paramString

---@class Marker.ParamCharCollapsed -- Collapsed by the draw function into clear instructions for how to draw it, instead of params
---@field text string
---@field xOffset number
---@field yOffset number
---@field color number[]
---@field paramsUsed Marker.ParamDictionary The params used in this char to collapse it
---@field x? number
---@field y? number

----------------------------------------------------------------------------------------------------
-- Text effects -----------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------

-- Effects not added to the order will not be registered
marker.charEffectsOrder = {
    "color",
    "tint",

    "wave",
    "harmonica",
    "shatter",

    "text",
    "corrupt"
}

-- Effects applied per character, most effects belong here
---@type table<string, fun(char: Marker.ParamCharCollapsed, arg: string, time: number, charIndex: integer, charPrevious?: Marker.ParamCharCollapsed): Marker.ParamCharCollapsed[]?>
marker.charEffects = {}

marker.charEffects.color = function (char, arg)
    char.color = marker.colors[arg] or marker.colors.default or {1,1,1}
end
marker.charEffects.tint = marker.charEffects.color -- Just a color on top of color

marker.charEffects.wave = function (char, arg, time, charIndex)
    local amount = tonumber(arg) or 1
    char.yOffset = char.yOffset + math.sin((time * 10) - (charIndex / 2)) * amount
end
marker.charEffects.harmonica = function (char, arg, time, charIndex)
    local amount = tonumber(arg)
    amount = amount or 1
    char.xOffset = char.xOffset + math.sin((time * 10) - (charIndex / 2)) * amount
end

marker.charEffects.text = function (char, arg, time, charIndex, charPrevious)
    local replacementChars = {}
    for pos, charCode in utf8.codes(arg) do
        local nextChar = utf8.char(charCode)
        replacementChars[#replacementChars+1] = {
            text = nextChar,
            xOffset = 0,
            yOffset = 0,
            color = {1, 1, 1},
            paramsUsed = char.paramsUsed
        }
    end

    return replacementChars
end

local corruptChars = {'#', '$', '%', '&', '@', '=', '?', '6', '<', '>'}
marker.charEffects.corrupt = function (char, arg, time, charIndex, charPrevious)
    local speed = tonumber(arg) or 1
    local progress = math.floor(time * 20 * speed)

    local seedPrevious = love.math.getRandomSeed()
    local charSeed = utf8.codepoint(char.text) + progress
    love.math.setRandomSeed(charSeed)

    local pickedCharIndex = love.math.random(1, #corruptChars)

    char.text = corruptChars[pickedCharIndex]
    love.math.setRandomSeed(seedPrevious)
end

marker.charEffects.shatter = function (char, arg, time, charIndex, charPrevious)
    local amount = (tonumber(arg) or 1) * 4

    local seedPrevious = love.math.getRandomSeed()
    local charSeed = utf8.codepoint(char.text) + charIndex
    love.math.setRandomSeed(charSeed)

    local xOffset = math.floor((love.math.random() - 0.5) * amount + 0.5)
    local yOffset = math.floor((love.math.random() - 0.5) * amount + 0.5)
    char.xOffset = char.xOffset + xOffset
    char.yOffset = char.yOffset + yOffset

    love.math.setRandomSeed(seedPrevious)
end

-- Text effects not added to the order will not be registered
marker.textEffectsOrder = {
    "typewriter"
}

-- Effects applied on the entire text as a whole, only a few effects need to see and modify the full text
---@type table<string, fun(collapsedParamString: Marker.ParamCharCollapsed[], time: number, timePrevious: number)>
marker.textEffects = {}

local typePauseChars = {
    ["."] = true,
    [","] = true,
    [":"] = true,
    [";"] = true
}
local typeSkipChars = {
    [""] = true,
    [" "] = true,
    ["\n"] = true
}
marker.textEffects.typewriter = function (collapsedParamString, time, timePrevious)
    local timeAccumulated = 0
    local typeInstant = false ---@type any
    for charIndex = 1, #collapsedParamString do
        local char = collapsedParamString[charIndex]
        local nextChar = collapsedParamString[charIndex+1]
        local paramsUsed = char.paramsUsed

        typeInstant = paramsUsed["typewriter-appear"]
        local speedMult = tonumber(typeInstant)

        if paramsUsed.typewriter then
            local arg = paramsUsed.typewriter
            local num = 1 / ((tonumber(arg) or 1) * 10)
            if speedMult then num = num / speedMult end
            if typeSkipChars[char.text] then num = 0 end
            if typePauseChars[char.text] then num = num * 2 end

            local appearProgress
            if typeInstant then
                appearProgress = (time - timeAccumulated) / num
                appearProgress = math.max(0, appearProgress)
                appearProgress = math.min(1, appearProgress)
                if typeInstant and not speedMult then
                    appearProgress = math.floor(appearProgress)
                end

                if nextChar and nextChar.paramsUsed["typewriter-appear"] then
                    num = 0
                end
            end

            if appearProgress then
                char.color = {char.color[1], char.color[2], char.color[3], appearProgress}
            end

            if timeAccumulated > time then
                char.text = ""
            else
                if timeAccumulated > timePrevious and num > 0 and not typeInstant then
                    if marker.callbacks.typewriter then marker.callbacks.typewriter({charTable = char}) end
                end
            end
            timeAccumulated = timeAccumulated + num
        end
    end
end

----------------------------------------------------------------------------------------------------
-- Generic local functions ------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------

---@param str string
---@return string
local function trim(str)
    return (str:gsub("^%s*(.-)%s*$", "%1"))
end

---@param t table Table to copy
---@param target? table Table to copy the values to
---@return table
local function shallowCopy(t, target)
    local newTable = target or {}
    for key, value in pairs(t) do
        newTable[key] = value
    end
    return newTable
end

----------------------------------------------------------------------------------------------------
-- Petite local functions ------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------

--- Parses and deletes the escape characters
---@param str any
---@return string
---@return integer count
local function parseEscapes(str)
    return string.gsub(str, "\\(.)", "%1")
end

---@param str string
---@return boolean
local function isParamUnsetKeyword(str)
    for i = 1, #paramUnsetKeywords do
        if str == paramUnsetKeywords[i] then return true end
    end
    return false
end

----------------------------------------------------------------------------------------------------
-- Meaty local functions --------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------

--- Attempts to find a tag in the input string
---@param str string String to find tag in
---@param searchStart integer The number where to start the search at
---@return integer|nil tagStart The index in the string at which this match starts, or nil if a match wasn't found
---@return integer|nil tagEnd The index in the string at which this match ends, or nil if a match wasn't found
---@return string|nil tag The text of the tag or nil if this isn't a tag
local function findTagInString(str, searchStart)
    -- Find a tag, leave if there is none
    local startIndex, endIndex, match = string.find(str, "(%b[])", searchStart)
    if not startIndex then return end

    -- Early returned if the tag is escaped
    local charBefore = string.sub(str, startIndex-1, startIndex-1)
    local charBeforeCharBefore = string.sub(str, startIndex-2, startIndex-2)
    if charBefore == "\\" and charBeforeCharBefore ~= "\\" then -- It's escaped, and the escape isn't escaped
        return startIndex, endIndex
    end

    -- Make sure it's actually a tag (double brackets) and not just a set of brackets
    if not(string.sub(match, 2, 2) == "[" and string.sub(match, -2, -2) == "]") then
        return startIndex, endIndex
    end

    -- We found a tag, return it
    return startIndex, endIndex, string.sub(match, 3, -3)
end

---@param str string The tag text (excluding the [[ and ]] at the start and end)
---@return Marker.ParamDictionary params Table of params (as keys) and their values as strings, or as false if the param has been unset
---@return boolean glueTagged
local function decodeTag(str)
    local glueTagged = false
    if string.sub(str, 1, 1) == "~" then
        str = string.sub(str, 2, -1)
        glueTagged = true
    end

    ---@type Marker.ParamDictionary
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

    return params, glueTagged
end

--- Takes a string and removes all tags from it, returning the stripped string and a table of the parsed tags instead
---@param str string The string to parse
---@return string strippedString The string without any tags
---@return table<integer, Marker.ParamDictionary> params A dictionary with character indices and the params that start there
local function stripStringOfTags(str)
    ---@type table<integer, Marker.ParamDictionary>
    local tags = {}
    local previousTag = nil
    local searchStart = 1
    while true do
        -- Find a match for a tag, break if there is none
        local tagStart, tagEnd, tagText = findTagInString(str, searchStart)
        if not tagStart or not tagEnd then
            break
        end

        -- If a tag has been found
        if tagText then
            -- Track tag
            -- Edit the tag at this location, or if it doesnt exist, copy the values of the previous tag if there was one
            local currentTag = tags[tagStart] or (previousTag and shallowCopy(previousTag) or {})
            local decodedTag, glueTagged = decodeTag(tagText)
            for param, value in pairs(decodedTag) do
                currentTag[param] = value and value or nil -- Convert falsey values to nil to remove them from the table fully
            end
            tags[tagStart] = currentTag
            previousTag = currentTag

            -- Remove tag from string and adjust searchStart accordingly
            str = string.sub(str, 1, tagStart-1) .. string.sub(str, tagEnd+1)
            searchStart = tagStart
        else
            -- No tag, just move the searchStart
            searchStart = tagStart + 1
        end
    end

    -- Remove the escaping backslashes
    str = parseEscapes(str)

    return str, tags
end

---@param strippedString string
---@param params table<integer, Marker.ParamDictionary>
---@return Marker.ParamChar[]
local function convertStrippedStringToParamString(strippedString, params)
    ---@type Marker.ParamChar[]
    local tagString = {}
    local currentParams = {}
    for pos, char in utf8.codes(strippedString) do
        if params[pos] then
            currentParams = params[pos]
        end

        tagString[#tagString+1] = {text = utf8.char(char), params = currentParams}
    end

    return tagString
end

--- Converts a string to a paramString
---@param str string The input string
---@return Marker.ParamChar[] paramString The output paramString
---@return string strippedString The input string stripped of all of its tags
local function stringToTagString(str)
    local strippedString, params = stripStringOfTags(str)
    local paramString = convertStrippedStringToParamString(strippedString, params)
    return paramString, strippedString
end

local function applyCharEffectsOnCollapsedParamChar(collapsedParamChar, time, stringIndex, collapsedCharPrevious, ignoreReplacementChars)
    local charParams = collapsedParamChar.paramsUsed
    local replacementChars

    for charEffectIndex = 1, #marker.charEffectsOrder do
        local charEffectName = marker.charEffectsOrder[charEffectIndex]
        local paramValue = charParams[charEffectName]

        if paramValue then
            local replacementCharOutput = marker.charEffects[charEffectName](collapsedParamChar, paramValue, time, stringIndex, collapsedCharPrevious)

            if collapsedCharPrevious and replacementCharOutput and collapsedCharPrevious.paramsUsed[charEffectName] then
                -- Replacement output is only applied to the first character, the rest of the characters must just get deleted
                replacementCharOutput = {}
            end
            replacementChars = replacementCharOutput or replacementChars
        end
    end

    -- Apply effects again on replacement characters
    local replacementCharPrevious = collapsedCharPrevious
    if replacementChars and not ignoreReplacementChars then
        for replacementCharIndex = 1, #replacementChars do
            local replacementChar = replacementChars[replacementCharIndex]
            applyCharEffectsOnCollapsedParamChar(replacementChar, time, stringIndex + replacementCharIndex - 1, replacementCharPrevious, true)
            replacementCharPrevious = replacementChar
        end
    end

    return replacementChars
end

---@param paramString Marker.ParamChar[]
---@return Marker.ParamCharCollapsed[]
---@return Marker.ParamDictionary
local function collapseParamString(paramString, time)
    ---@type Marker.ParamCharCollapsed[]
    local collapsedParamString = {}
    local stringIndex = 1
    local charsEncountered = 0
    local collapsedCharPrevious
    local effectsEncountered = {}
    while stringIndex <= #paramString do
        charsEncountered = charsEncountered + 1

        local paramChar = paramString[stringIndex]
        local charParams = paramChar.params

        for eff, value in pairs(charParams) do
            effectsEncountered[eff] = value
        end

        local collapsedParamChar = {
            text = paramChar.text,
            xOffset = 0,
            yOffset = 0,
            color = {1, 1, 1},
            paramsUsed = charParams
        }

        local replacementChars = applyCharEffectsOnCollapsedParamChar(collapsedParamChar, time, charsEncountered, collapsedCharPrevious)

        if replacementChars then
            for replacementCharIndex = 1, #replacementChars do
                collapsedParamString[#collapsedParamString+1] = replacementChars[replacementCharIndex]
            end
            charsEncountered = charsEncountered + #replacementChars - 1
        else
            collapsedParamString[#collapsedParamString+1] = collapsedParamChar
        end

        stringIndex = stringIndex + 1
        collapsedCharPrevious = collapsedParamChar
    end
    return collapsedParamString, effectsEncountered
end

----------------------------------------------------------------------------------------------------
-- The markedText class ----------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------

-- Holds different functions for drawing the text differently based on the textAlign property
local drawFunctions = {}

---Assumes the x and y of the characters have been set
---@param collapsedParamString Marker.ParamCharCollapsed[]
---@param boxHeight number
---@param textHeight number
---@param verticalAlign number
---@param font love.Font
local function renderCollapsedParamString(collapsedParamString, boxHeight, textHeight, verticalAlign, font)
    local textUnusedSpace = boxHeight - textHeight
    local verticalAlignOffset = (textUnusedSpace + textUnusedSpace * verticalAlign)/2

    local fontPrevious = love.graphics.getFont()
    local cr, cg, cb, ca = love.graphics.getColor()
    love.graphics.setFont(font)
    for paramCharIndex = 1, #collapsedParamString do
        local paramChar = collapsedParamString[paramCharIndex]
        local charX = paramChar.x
        local charY = paramChar.y
        local charText = paramChar.text
        local charColor = paramChar.color
        local charXOffset = paramChar.xOffset
        local charYOffset = paramChar.yOffset

        charX = math.floor(charX + charXOffset)
        charY = math.floor(charY + charYOffset + verticalAlignOffset)

        love.graphics.setColor(charColor)
        love.graphics.print(charText, charX, charY)
    end
    love.graphics.setFont(fontPrevious)
    love.graphics.setColor(cr, cg, cb, ca)
end

local function extractLine(collapsedParamString, lineCharacterIndex, font, maxWidth)
    local lineCharacterCount = 0
    local lineWidth = 0
    local lineWidthUntilLastWhitespace
    local lineOverflowed = false
    local stringEndFound = false
    local lastWhitespaceAtCount
    while true do
        local currentCharIndex = lineCharacterIndex + lineCharacterCount
        local paramChar = collapsedParamString[currentCharIndex]
        if not paramChar then
            stringEndFound = true
            break
        end
        if paramChar.text == "\n" then
            lineCharacterCount = lineCharacterCount + 1
            break
        end

        if paramChar.text == " " then
            lastWhitespaceAtCount = lineCharacterCount + 1 -- +1 to include the whitespace in the count
            lineWidthUntilLastWhitespace = lineWidth
        end

        local charWidth = font:getWidth(paramChar.text)
        if lineWidth + charWidth > maxWidth and lineCharacterCount > 0 then
            -- We've reached max width, + one character per line minimum to avoid an infinite loop
            lineOverflowed = true

            -- Only split at spaces if possible
            lineCharacterCount = lastWhitespaceAtCount or lineCharacterCount
            lineWidth = lineWidthUntilLastWhitespace or lineWidth
            break
        end

        -- We're safe to add this character to the current line
        lineCharacterCount = lineCharacterCount + 1
        lineWidth = lineWidth + charWidth
    end
    return lineCharacterCount, lineWidth, lineOverflowed, stringEndFound
end

local verticalAlignEnum = {
    top = -1,
    middle = 0,
    center = 0,
    bottom = 1
}

function drawFunctions.invalid(markedText)
    local x = markedText.x
    local y = markedText.y
    local fontPrevious = love.graphics.getFont()
    love.graphics.setFont(markedText.font)
    love.graphics.print("Invalid text align property: '" .. tostring(markedText.textAlign) .. "'", x, y)
    love.graphics.setFont(fontPrevious)
end

---@param markedText Marker.MarkedText
---@param alignment? number
function drawFunctions.default(markedText, alignment)
    alignment = alignment or -1

    local x = markedText.x
    local y = markedText.y
    local maxWidth = markedText.maxWidth
    local paramString = markedText.paramString
    local font = markedText.font
    local lineHeight = font:getHeight()

    local collapsedParamString, effectsEncountered = collapseParamString(paramString, markedText.time)

    local stringEndFound = false
    local lineCharacterIndex = 1
    local lineIndex = 1
    while not stringEndFound do
        local lineCharacterCount, lineWidth, lineOverflowed
        lineCharacterCount, lineWidth, lineOverflowed, stringEndFound = extractLine(collapsedParamString, lineCharacterIndex, font, maxWidth)

        local textBlockOffset = 0
        if markedText.doRelativeXAlign then
            textBlockOffset = -(maxWidth + maxWidth * alignment)/2
        end
        local lineUnusedSpace = maxWidth - lineWidth
        local alignmentOffset = (lineUnusedSpace + lineUnusedSpace * alignment)/2
        local lineWidthProgress = 0
        for charIndex = lineCharacterIndex, lineCharacterIndex + lineCharacterCount - 1 do
            local paramChar = collapsedParamString[charIndex]
            local charText = paramChar.text

            local charX = x + lineWidthProgress + alignmentOffset + textBlockOffset
            local charY = y + (lineIndex - 1) * lineHeight

            paramChar.x = charX
            paramChar.y = charY

            lineWidthProgress = lineWidthProgress + font:getWidth(charText)
        end

        lineCharacterIndex = lineCharacterIndex + lineCharacterCount
        lineIndex = lineIndex + 1
    end

    local textHeight = lineHeight * (lineIndex - 1)
    local verticalAlign = verticalAlignEnum[markedText.verticalAlign]

    -- Apply text effects
    for textEffectIndex = 1, #marker.textEffectsOrder do
        local textEffectName = marker.textEffectsOrder[textEffectIndex]
        if effectsEncountered[textEffectName] then
            marker.textEffects[textEffectName](collapsedParamString, markedText.time, markedText.timePrevious)
        end
    end

    renderCollapsedParamString(collapsedParamString, markedText.boxHeight, textHeight, verticalAlign, font)
end

drawFunctions.left = function (markedText) return drawFunctions.default(markedText, -1) end
drawFunctions.right = function (markedText) return drawFunctions.default(markedText, 1) end
drawFunctions.center = function (markedText) return drawFunctions.default(markedText, 0) end
drawFunctions.middle = drawFunctions.center

---@class Marker.MarkedText
local markedTextMetatable = {}
markedTextMetatable.__index = markedTextMetatable

--- Draws the text, optionally overriding the set X and Y coordinates with the given parameters
function markedTextMetatable:draw()
    local drawFunction = drawFunctions[self.textAlign] or drawFunctions.invalid
    drawFunction(self)
end

-- Updates the text to animate
---@param dt number
function markedTextMetatable:update(dt)
    self.timePrevious = self.time
    self.time = self.time + dt
end

--- Calculates and returns the width and height the text takes up
---@return number
---@return number
function markedTextMetatable:getSize()
    local width = 0
    local height = 0
    local collapsedParamString = collapseParamString(self.paramString, self.time)
    local lineCharacterIndex = 1
    local stringEndFound = false
    while not stringEndFound do
        local lineCharacterCount, lineWidth, lineOverflowed
        lineCharacterCount, lineWidth, lineOverflowed, stringEndFound = extractLine(collapsedParamString, lineCharacterIndex, self.font, self.maxWidth)
        lineCharacterIndex = lineCharacterIndex + lineCharacterCount
        width = math.max(width, lineWidth)
        height = height + self.font:getHeight()
    end
    return width, height
end

--- Parses a new string and sets the MarkedText to it
---@param str string
function markedTextMetatable:setText(str)
    local paramString, strippedString = stringToTagString(str)
    self.rawString = str
    self.strippedString = strippedString
    self.paramString = paramString
end

local defaultFont = love.graphics.newFont()
--- Creates a new MarkedText instance
---@param str? string The tagged string to parse and set the text to (Default is empty string)
---@param font? love.Font The font used to draw this text
---@param x? number The X location to place the text at (Default is 0)
---@param y? number The Y location to place the text at (Default is 0)
---@param maxWidth? number The maximum width the text can take up (Default is infinity)
---@param textAlign? Marker.TextAlign The horizontal alignment of the text (Default is "left")
---@param verticalAlign? Marker.VerticalAlign The vertical alignment of the text (Default is "top")
---@param boxHeight? number The reference height of a box this text lays in, used for vertical alignment. (Default is 0 - aligns relatively to X and Y)
---@return Marker.MarkedText markedText
function marker.newMarkedText(str, font, x, y, maxWidth, textAlign, verticalAlign, boxHeight, doRelativeXAlign)
    str = str or ""
    font = font or defaultFont
    x = x or 0
    y = y or 0
    maxWidth = maxWidth or math.huge
    textAlign = textAlign or "left"
    verticalAlign = verticalAlign or "top"
    boxHeight = boxHeight or 0
    doRelativeXAlign = doRelativeXAlign or false

    local paramString, strippedString = stringToTagString(str)

    ---@type Marker.MarkedText
    local markedText = {
        x = x,
        y = y,
        font = font,
        maxWidth = maxWidth,
        time = 0,
        timePrevious = 0,
        textAlign = textAlign,
        verticalAlign = verticalAlign,
        boxHeight = boxHeight,
        doRelativeXAlign = doRelativeXAlign,
        rawString = str,
        strippedString = strippedString,
        paramString = paramString,
    }

    setmetatable(markedText, markedTextMetatable)
    return markedText
end

return marker