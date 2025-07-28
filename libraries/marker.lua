----------------------------------------------------------------------------------------------------
-- A messy but featureful LÖVE text rendering library
-- written by yours truly, CrispyBun.
-- crispybun@pm.me
----------------------------------------------------------------------------------------------------
--[[
MIT License

Copyright (c) 2025 Ava "CrispyBun" Špráchalů

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

local utf8 = require 'utf8'

local marker = {}

-- Types --------------------------------------------------------------------------------------------

--- The object capable of generating and drawing an animated text with effects
---@class Marker.MarkedText
---@field x number The X coordinate of the text
---@field y number The Y coordinate of the text
---@field time number The current time (in seconds), relative to some unknown starting point. Used by some effects.
---@field textVariables table Variables which some text effects can read and display. If the variable isn't found here, the effects will then look into the root `marker.textVariables` table. You shouldn't overwrite this table completely, as that would clear necessary metatable data.
---@field wrapLimit number How wide the text is allowed to be before it must wrap
---@field textAlign Marker.TextAlign The horizontal alignment of the text
---@field verticalAlign Marker.VerticalAlign The vertical alignment of the text
---@field alignBox [number, number] The reference textbox size ([x, y]) the text is aligned in
---@field font Marker.Font The font used to generate the text
---@field timePrevious number The `time` value from the previous `update()`.
---@field inputString string The string used to generate the text
---@field chars Marker.MarkedChar[] The generated MarkedChars
---@field effectAllowlist table<string, boolean>? If set, only the effects in this allowlist will be processed.
---@field topLevelEffects Marker.EffectData[] Effects in this list will be added to all generated chars when `generate()` is called. They can still be turned off by the input string with an appropriate closing tag (</*>) if parsing is enabled.
---@field parsingEnabed boolean Whether or not effect <tags> will be parsed from the input string when `generate()` is called.
---@field ignoreStretchOnLastLine boolean True by default, makes alignments like "justify" look much better on paragraph ending lines.
---@field updateRequested boolean If true, the text re-apply all its effects to the text on the next call to `update()` and reset this value back to `false`. May be set to true by some effects.
---@field layoutRequested boolean If true, the text will call `layout()` on the next call to `update()` and reset this value back to `false`. May be set to true by some effects.
local MarkedText = {}
local MarkedTextMT = {__index = MarkedText}

--- A single char of a MarkedText
---@class Marker.MarkedChar
---@field str string The string the char represents
---@field renderedStr? string The string the char will actually render to the screen instead of the assigned `str`. Gets reset each time text effects are about to be processed.
---@field font Marker.Font The font of the char
---@field colorR number The red component of the char's color.  Gets reset each time text effects are about to be processed.
---@field colorG number The green component of the char's color.  Gets reset each time text effects are about to be processed.
---@field colorB number The blue component of the char's color.  Gets reset each time text effects are about to be processed.
---@field colorA number The alpha component of the char's color.  Gets reset each time text effects are about to be processed.
---@field xPlacement number The X coordinate of the char
---@field yPlacement number The Y coordinate of the char
---@field xOffset number Offset from the X coordinate. Gets reset each time text effects are about to be processed.
---@field yOffset number Offset from the Y coordinate. Gets reset each time text effects are about to be processed.
---@field disabled boolean May be set to true when getting laid out by the MarkedText (won't render and should be ignored for most purposes). Gets reset on layout.
---@field effects Marker.EffectData[] All the effects applied to this char
local MarkedChar = {}
local MarkedCharMT = {__index = MarkedChar}

---@class Marker.Effect
---@field charFn? fun(char: Marker.MarkedChar, attributes: table<string, string?>, info: Marker.MarkedTextEffectInfo): Marker.EffectReturnKeyword? Receives each char the effect affects.
---@field stringFn? fun(charView: Marker.MarkedCharView, attributes: table<string, string?>, info: Marker.MarkedTextEffectInfo): Marker.EffectReturnKeyword? Receives a view for each continuous chain of chars the effect affects.
---@field textFn? fun(text: Marker.MarkedText): Marker.EffectReturnKeyword? Gets the entire text (if the effect is present at least once in it), after all other effect processing is done.
local Effect = {}
local EffectMT = {__index = Effect}

--- The optional return value for effects which can request things to happen in the MarkedText.
--- 
--- * `"update"` should be used if the effect might look different next frame (e.g. "shake" effect).
---              Note that this will cause *all* the effects to be updated next frame, not just the one requesting an update.
--- * `"layout"` should be used if the text needs to re-layout itself to look correct after applying the effect.
---              It does not need to be used if the effect only calls `CharView:replaceContents()`, as that will request a layout automatically when needed.
---@alias Marker.EffectReturnKeyword
---|'"none"' # The effect doesn't request for anything to happen
---|'"update"' # The effect is requesting another update next frame
---|'"layout"' # The effect made structural changes to the text and is requesting a layout to happen
---|'"layout+update"' # Requests both a layout to happen now and an update to happen next frame

--- Info passed to effects about the text and current char relative to the effect
---@class Marker.MarkedTextEffectInfo
---@field charIndex integer The index of the char currently being processed.
---@field symbolIndex? integer Like charIndex, but chars that aren't symbols (empty string, control characters) don't add to this index. This is only available for char scope functions.
---@field time number The time value (in seconds) set in the text object.
---@field timePrevious number The time value from the previous update
---@field textVariables table The `textVariables` field of the text object.

---@class Marker.MarkedCharView
---@field private _indexFirst integer
---@field private _indexLast integer
---@field private _chars Marker.MarkedChar[]
---@field private _contentsWereReplaced boolean
local MarkedCharView = {}
local MarkedCharViewMT = {__index = MarkedCharView}

--- An abstract font class for drawing characters in some way
---@class Marker.Font
local AbstractFont = {}
local AbstractFontMT = {__index = AbstractFont}

--- An implementation for Marker.Font, mapping its functionality to regular love fonts
---@class Marker.LoveFont : Marker.Font
---@field font love.Font
local LoveFont = {}
local LoveFontMT = {__index = LoveFont}

---@class Marker.WrapInfo
---@field lineIndices number[] Alternating start and end indices of each line (line1start, line1end, line2start, line2end, ...)
---@field lineWidths number[] The width of each line
---@field lineHeights number[] The height of each line
---@field textHeight number The height of the whole text
---@field spaceCounts number[] The amount of space chars in each line
---@field symbolCounts number[] The amount of renderable non-special symbols in each line

---@alias Marker.TextAlign
---| '"start"' # Aligns to the left
---| '"center"' # Aligns to the center
---| '"end"' # Aligns to the right
---| '"middle"' # Same as "center"
---| '"left"' # Same as "start"
---| '"right"' # Same as "end"
---| '"justify"' # Spreads out the words in each line to span the entire alignBox width
---| '"letterspace"' # Adjusts letter spacing in each line to span the entire alignBox width

---@alias Marker.VerticalAlign
---| '"start"' # Aligns to the top
---| '"center"' # Aligns to the center
---| '"end"' # Aligns to the bottom
---| '"middle"' # Same as "center"
---| '"top"' # Same as "start"
---| '"bottom"' # Same as "end"

-- Data about an effect generated by parsing the tags in an array of MarkedChars.
-- The same EffectData instance is referenced by multiple MarkedChars if they point to the same effect.
---@class Marker.EffectData
---@field name string The name of the effect
---@field attributes table<string, string?> The attributes assigned to the effect

-- Misc --------------------------------------------------------------------------------------------

--- Variables which some text effects can read and display, most notably used by the `<var ref="*"/>` effect.
marker.textVariables = {}

--- The metatable assigned to `MarkedText.textVariables` tables so they default back to the root table.
marker.textVariablesTextMT = {__index = marker.textVariables}

--- A table in which some effects define callbacks in to be listened to by the program.
marker.effectCallbacks = {}

--- Called for every typed character by the typewriter effect, with the associated attributes for the effect at that char.
---@type fun(char: Marker.MarkedChar, attributes: table<string, string?>)?
marker.effectCallbacks.typewriter = nil

--- Defined colors for chars. Can be overwritten with a completely different table.
---@type table<string, [number, number, number, number?]?>
marker.colors = {
    red = {1, 0.1, 0.15},
    green = {0, 1, 0.1},
    blue = {0.2, 0.2, 1},
}

--- The color chars are initialized to. You can change this once before using the library but it shouldn't really be changed at runtime.
marker.defaultColor = {1,1,1}

--- This can be defined to handle chars using color names that aren't defined in the colors table.
--- This could, for example, look for the color in another table elsewhere, or resolve assigned string hex color values.
---@type (fun(colorName: string): [number, number, number, number?]?)?
marker.resolveUnknownColor = nil

--- Gets the color associated with the given color name, or if there is none, returns the default color.
---@param colorName string?
---@return [number, number, number, number?]
function marker.getColor(colorName)
    if not colorName then return marker.defaultColor end

    local color = marker.colors[colorName]
    if not color and marker.resolveUnknownColor then color = marker.resolveUnknownColor(colorName) end

    return color or marker.defaultColor
end

--- Takes in an attribute and returns `true` unless the attribute is unset or a falsy keyword.
---@param attribute string?
---@return boolean
function marker.attributeToBool(attribute)
    if not attribute then return false end
    if attribute == "" then return false end

    attribute = string.lower(attribute)
    if attribute == "false" then return false end
    if attribute == "off" then return false end

    return true
end

-- MarkedText --------------------------------------------------------------------------------------

--- Creates a new fancy MarkedText object
---@param str? string
---@param font? love.Font|Marker.Font
---@param x? number
---@param y? number
---@param wrapLimit? number
---@param textAlign? Marker.TextAlign
---@return Marker.MarkedText
function marker.newMarkedText(str, font, x, y, wrapLimit, textAlign)
    if type(font) == "userdata" then
        ---@diagnostic disable-next-line: param-type-mismatch
        font = marker.newWrappedLoveFont(font)
    end

    local alignBoxWidth = (wrapLimit and wrapLimit ~= math.huge) and wrapLimit or 0

    ---@type Marker.MarkedText
    local markedText = {
        x = x or 0,
        y = y or 0,
        time = 0,
        textVariables = setmetatable({}, marker.textVariablesTextMT),
        wrapLimit = wrapLimit or math.huge,
        textAlign = textAlign or "start",
        verticalAlign = "start",
        alignBox = {alignBoxWidth, 0},
        ---@diagnostic disable-next-line: assign-type-mismatch
        font = font or marker.getDefaultFont(),
        timePrevious = 0,
        inputString = str or "",
        chars = {},
        topLevelEffects = {},
        parsingEnabed = true,
        ignoreStretchOnLastLine = true,
        updateRequested = false,
        layoutRequested = false,
    }
    setmetatable(markedText, MarkedTextMT)

    markedText:generate()

    return markedText
end

--- Updates the effects on the text. This is required for effects that change over time to work.
--- 
--- If `dt` is supplied, it gets added to the internal `MarkedText.time` value.
--- If it isn't, the time value should be updated manually in some other way.
---@param dt? number
function MarkedText:update(dt)
    dt = dt or 0
    self.timePrevious = self.time
    self.time = self.time + dt

    if self.updateRequested then
        self.updateRequested = false
        self:processEffects()
    end

    if self.layoutRequested then
        self.layoutRequested = false
        self:layout()
    end
end

--- Sets the text's position. The layout does not need to be updated.
---@param x number
---@param y number
function MarkedText:setPosition(x, y)
    self.x = x
    self.y = y
end

--- Will make the text call `layout()` on itself on the next update.
function MarkedText:requestLayout()
    self.layoutRequested = true
end

--- Sets the text's wrap limit. The layout must be updated for this to take effect.
---@param wrapLimit number
function MarkedText:setWrapLimit(wrapLimit)
    self.wrapLimit = wrapLimit
end

--- Sets the alignment of the text. The layout must be updated for this to take effect.
---@param textAlign Marker.TextAlign
---@param verticalAlign? Marker.VerticalAlign
function MarkedText:setAlign(textAlign, verticalAlign)
    self.textAlign = textAlign
    self.verticalAlign = verticalAlign or self.verticalAlign
end

--- Sets the reference textbox size the text is aligned in.
--- If a wrapLimit was specified in the constructor, the alignBox
--- width will have been set to the wrapLimit automatically.
--- 
--- The layout must be updated for this to take effect.
---@param x number
---@param y? number
function MarkedText:setAlignBox(x, y)
    self.alignBox[1] = x
    self.alignBox[2] = y or 0
end

--- Regenerates the entire MarkedText, optionally using a different input string.
--- If the actual text is unchanged, and all that's desired is an update to the layout,
--- it might be better to call `layout()` instead.
---@param str? string
function MarkedText:generate(str)
    str = str or self.inputString
    self.inputString = str

    ---@type Marker.MarkedChar[]
    local markedChars = {}

    local font = self.font

    for pos, code in utf8.codes(str) do
        local charStr = utf8.char(code)

        local markedChar = marker.newMarkedChar(charStr, 0, 0, font)

        if not self.parsingEnabed then
            for effectIndex = 1, #self.topLevelEffects do
                markedChar.effects[effectIndex] = self.topLevelEffects[effectIndex]
            end
        end

        markedChars[#markedChars+1] = markedChar
    end

    if self.parsingEnabed then
        local tagStack = {}

        for effectIndex = 1, #self.topLevelEffects do
            tagStack[effectIndex] = self.topLevelEffects[effectIndex]
        end

        self.chars = marker.parser.parse(markedChars, tagStack)
    else
        self.chars = markedChars
    end

    self:processEffects()
    self:layout()
    self.layoutRequested = false
end

---@param x? number
---@param y? number
function MarkedText:draw(x, y)
    x = x or self.x
    y = y or self.y

    local chars = self.chars
    for charIndex = 1, #chars do
        local char = chars[charIndex]
        char:draw(x, y)
    end
end

--- Lays out the characters in the text to the correct position.
--- Called automatically by `MarkedText:generate()`.
function MarkedText:layout()
    local wrapInfo = self:getWrap()
    local chars = self.chars

    local lineIndices = wrapInfo.lineIndices
    local lineWidths = wrapInfo.lineWidths
    local lineHeights = wrapInfo.lineHeights
    local textHeight = wrapInfo.textHeight
    local spaceCounts = wrapInfo.spaceCounts
    local symbolCounts = wrapInfo.symbolCounts

    local alignBoxX = self.alignBox[1]
    local alignBoxY = self.alignBox[2]

    local rowShiftFactor = 0
    local textAlign = self.textAlign
    if textAlign == "center" or textAlign == "middle" then rowShiftFactor = 0.5
    elseif textAlign == "end" or textAlign == "right" then rowShiftFactor = 1 end

    local columnShiftFactor = 0
    local verticalAlign = self.verticalAlign
    if verticalAlign == "center" or verticalAlign == "middle" then columnShiftFactor = 0.5
    elseif verticalAlign == "end" or verticalAlign == "bottom" then columnShiftFactor = 1 end

    local nextX = 0
    local nextY = 0

    nextY = nextY - columnShiftFactor * textHeight + columnShiftFactor * alignBoxY

    for lineIndex = 1, #lineWidths do
        local lineStartCharIndex = lineIndices[lineIndex*2-1]
        local lineEndCharIndex = lineIndices[lineIndex*2]

        local lineWidth = lineWidths[lineIndex]
        local lineHeight = lineHeights[lineIndex]
        local spaceCount = spaceCounts[lineIndex]
        local symbolCount = symbolCounts[lineIndex]
        local lastCharIsLineEnd = chars[lineEndCharIndex]:isLineEnding()

        local horizontalWiggleRoom = alignBoxX - lineWidth

        -- proper justify alignment should also adjust letter spacing to an extent,
        -- as well as maybe have the ability to shrink spaces too, but the simple enough
        -- space stretching approach is good enough for now.
        local spaceStretch = (textAlign == "justify" and spaceCount > 0) and (horizontalWiggleRoom / spaceCount) or 0
        local symbolStretch = (textAlign == "letterspace" and symbolCount >= 2) and (horizontalWiggleRoom / (symbolCount-1)) or 0
        spaceStretch = math.max(spaceStretch, 0)

        if self.ignoreStretchOnLastLine and (lineIndex == #lineWidths or lastCharIsLineEnd) then
            spaceStretch = 0
            symbolStretch = 0
        end

        local seenSymbols = 0

        nextX = nextX - rowShiftFactor * lineWidth + rowShiftFactor * alignBoxX

        local charPrevious ---@type Marker.MarkedChar?
        for charIndex = lineStartCharIndex, lineEndCharIndex do
            local char = chars[charIndex]
            local charWidth = char:getWidth()
            local charHeight = char:getHeight(true)
            local charIsSpace = char:isSpace()
            local charIsSymbol = char:isSymbol()

            local extraSpacingLeft = 0
            local extraSpacingRight = 0

            if charIsSpace then
                extraSpacingLeft = extraSpacingLeft + spaceStretch / 2
                extraSpacingRight = extraSpacingRight + spaceStretch / 2
            end

            if charIsSymbol then
                seenSymbols = seenSymbols + 1
                extraSpacingLeft = extraSpacingLeft + ((seenSymbols == 1) and (0) or (symbolStretch/2))
                extraSpacingRight = extraSpacingRight + ((seenSymbols == symbolCount) and (0) or (symbolStretch/2))
            end

            local kerning = charPrevious and charPrevious:getKerning(char) or 0
            nextX = nextX + kerning
            nextX = nextX + extraSpacingLeft

            local placementOffsetX = 0
            local placementOffsetY = 0

            -- This approach looks really bad on mixed font sizes,
            -- mixed font baselines and mixed font line heights.
            -- What really should be done is have getWrap() determine line
            -- heights based on the highest ascent + highest descent value of the fonts,
            -- as well as return a table containing the baseline for each line. But,
            -- since I'm only really planning on using simple fonts with
            -- all line heights set to 1, I really don't care that much right now.
            placementOffsetY = placementOffsetY + (lineHeight - charHeight)

            char:setPlacement(nextX + placementOffsetX, nextY + placementOffsetY)

            nextX = nextX + charWidth
            nextX = nextX + extraSpacingRight

            charPrevious = char
        end

        nextX = 0
        nextY = nextY + lineHeight
    end
end

--- Calls and applies all the effects attached to the chars in the text.
--- Used internally.
function MarkedText:processEffects()
    local chars = self.chars
    local effectAllowlist = self.effectAllowlist

    local textScopeFunctions = {}
    local charView = marker.newMarkedCharView(chars, 1, 1)
    local updateRequested = false
    local layoutRequested = false

    ---@type Marker.MarkedTextEffectInfo
    local effectInfo = {
        charIndex = 0,
        time = self.time,
        timePrevious = self.timePrevious,
        textVariables = self.textVariables
    }

    -- First pass - reset visuals and apply string scope effects
    for charIndex = #chars, 1, -1 do
        local char = chars[charIndex]
        local effects = char.effects

        -- Reset values which don't require a re-layout on change
        -- (the effects are expected to set them again each call)
        char:resetVisuals()

        for effectIndex = 1, #effects do
            local effectData = effects[effectIndex]
            local effectName = effectData.name
            local effect = marker.registeredEffects[effectName]

            if effectAllowlist and (not effectAllowlist[effectName]) then
                effect = nil
            end

            if effect and effect.stringFn and self:isEffectStartIndex(charIndex, effectIndex) then
                charView:_init(chars, charIndex, self:findEffectEndIndex(charIndex, effectIndex))
                effectInfo.charIndex = charIndex
                effectInfo.time = self.time
                effectInfo.timePrevious = self.timePrevious
                effectInfo.textVariables = self.textVariables

                local fxRet = effect.stringFn(charView, effectData.attributes, effectInfo)

                updateRequested = updateRequested or (fxRet == "update" or fxRet == "layout+update")
                layoutRequested = layoutRequested or (fxRet == "layout" or fxRet == "layout+update")

                layoutRequested = layoutRequested or charView:wereContentsReplaced()
            end
        end
    end

    -- Second pass - apply char scope effects and gather text scope effects
    local symbolIndex = 0
    for charIndex = 1, #chars do
        local char = chars[charIndex]
        local effects = char.effects

        symbolIndex = symbolIndex + (char:isSymbol() and 1 or 0)

        for effectIndex = 1, #effects do
            local effectData = effects[effectIndex]
            local effectName = effectData.name
            local effect = marker.registeredEffects[effectName]

            if effectAllowlist and (not effectAllowlist[effectName]) then
                effect = nil
            end

            if effect and effect.charFn then
                effectInfo.charIndex = charIndex
                effectInfo.symbolIndex = symbolIndex
                effectInfo.time = self.time
                effectInfo.timePrevious = self.timePrevious
                effectInfo.textVariables = self.textVariables

                local fxRet = effect.charFn(char, effectData.attributes, effectInfo)

                updateRequested = updateRequested or (fxRet == "update" or fxRet == "layout+update")
                layoutRequested = layoutRequested or (fxRet == "layout" or fxRet == "layout+update")
            end

            if effect and effect.textFn then
                local alreadyAdded = false
                for fnIndex = 1, #textScopeFunctions do
                    if textScopeFunctions[fnIndex] == effect.textFn then
                        alreadyAdded = true
                        break
                    end
                end
                if not alreadyAdded then
                    textScopeFunctions[#textScopeFunctions+1] = effect.textFn
                end
            end
        end
    end

    -- Now just apply text scope effects
    for fnIndex = 1, #textScopeFunctions do
        local fxRet = textScopeFunctions[fnIndex](self)

        updateRequested = updateRequested or (fxRet == "update" or fxRet == "layout+update")
        layoutRequested = layoutRequested or (fxRet == "layout" or fxRet == "layout+update")
    end

    self.updateRequested = self.updateRequested or updateRequested
    self.layoutRequested = self.layoutRequested or layoutRequested
end

---@return Marker.WrapInfo
function MarkedText:getWrap()
    -- the eldritch function (close your eyes please)

    local chars = self.chars

    local lineIndices = { 1 }
    local lineWidths = {}
    local lineHeights = {}
    local spaceCounts = {}
    local symbolCounts = {}
    local textHeight = 0
    local currentLineWidth = 0
    local lineWidthSinceLastWrapPoint = 0
    local tallestLineChar = 0
    local tallestPreWrapPointLineChar = 0
    local currentSpaceCount = 0
    local currentSymbolCount = 0
    local lineSpaceCountSinceLastWrapPoint = 0
    local lineSymbolCountSinceLastWrapPoint = 0

    local wrapLimit = self.wrapLimit

    local idealLineEnd ---@type integer?
    local charPrevious ---@type Marker.MarkedChar?
    local wrapForcedOnNextChar = false

    local charIndex = 1
    local charsLength = #chars
    while charIndex <= charsLength do
        local char = chars[charIndex]
        local charWidth = char:getWidth()

        local kerning = charPrevious and charPrevious:getKerning(char) or 0
        local charWidthKerned = charWidth + kerning

        local charHeight = char:getHeight(true)
        local charIsSpace = char:isSpace()
        local charIsSymbol = char:isSymbol()

        char.disabled = false -- reset from possible previous getWrap call

        local charFits = (currentLineWidth + charWidthKerned <= wrapLimit) or (charWidthKerned <= 0)

        if (charFits and (not wrapForcedOnNextChar)) or (not charPrevious) then
            currentLineWidth = currentLineWidth + charWidthKerned
            lineWidthSinceLastWrapPoint = lineWidthSinceLastWrapPoint + charWidthKerned

            if charIsSpace then
                currentSpaceCount = currentSpaceCount + 1
                lineSpaceCountSinceLastWrapPoint = lineSpaceCountSinceLastWrapPoint + 1
            end

            if charIsSymbol then
                currentSymbolCount = currentSymbolCount + 1
                lineSymbolCountSinceLastWrapPoint = lineSymbolCountSinceLastWrapPoint + 1
            end

            if char:isIdealWrapPoint() then
                idealLineEnd = charIndex
                lineWidthSinceLastWrapPoint = 0
                lineSpaceCountSinceLastWrapPoint = 0
                lineSymbolCountSinceLastWrapPoint = 0
                tallestPreWrapPointLineChar = tallestLineChar -- this is for the previous char
            end

            tallestLineChar = math.max(tallestLineChar, charHeight)

            charPrevious = char
            wrapForcedOnNextChar = char:isLineEnding()

            charIndex = charIndex + 1
        else
            -- Wrap on current char instead of last idealLineEnd for these cases:
            if wrapForcedOnNextChar then idealLineEnd = nil end
            if char:isIdealWrapPoint() and char:isInvisibleInWrap() then idealLineEnd = nil end

            local lastLineEnd = idealLineEnd or (charIndex-1)
            charIndex = lastLineEnd+1

            local lastLineWidth = currentLineWidth - (idealLineEnd and lineWidthSinceLastWrapPoint or 0)
            local lastLineHeight = idealLineEnd and tallestPreWrapPointLineChar or tallestLineChar
            local lastLineSpaceCount = currentSpaceCount - (idealLineEnd and lineSpaceCountSinceLastWrapPoint or 0)
            local lastLineSymbolCount = currentSymbolCount - (idealLineEnd and lineSymbolCountSinceLastWrapPoint or 0)

            local lastLineEndChar = chars[lastLineEnd]

            -- If the wrapped char becomes invisible (if it's the only char on the line, it can't)
            if lastLineEndChar:isInvisibleInWrap() and lineIndices[#lineIndices] < lastLineEnd then
                local lastLineEndCharWidth = lastLineEndChar:getWidth() + chars[lastLineEnd-1]:getKerning(lastLineEndChar)
                lastLineWidth = lastLineWidth - lastLineEndCharWidth
                lastLineSpaceCount = lastLineSpaceCount - (lastLineEndChar:isSpace() and 1 or 0)
                lastLineSymbolCount = lastLineSymbolCount - (lastLineEndChar:isSymbol() and 1 or 0)

                lastLineEndChar.disabled = true
                lastLineEnd = lastLineEnd - 1
            else
                lastLineHeight = math.max(lastLineHeight, lastLineEndChar:getHeight(true))
            end

            -- line start char may only be invisible if the wrap wasn't forced by an explicit newline
            local nextLineStartChar = chars[charIndex]
            if nextLineStartChar:isInvisibleInWrap() and not wrapForcedOnNextChar then
                nextLineStartChar.disabled = true
                charIndex = charIndex + 1
            end

            charPrevious = nil
            idealLineEnd = nil
            wrapForcedOnNextChar = false
            currentLineWidth = 0
            lineWidthSinceLastWrapPoint = 0
            tallestLineChar = 0
            tallestPreWrapPointLineChar = 0
            currentSpaceCount = 0
            lineSpaceCountSinceLastWrapPoint = 0
            currentSymbolCount = 0
            lineSymbolCountSinceLastWrapPoint = 0

            -- Mark ending of last line and start of next line
            lineIndices[#lineIndices+1] = lastLineEnd
            lineIndices[#lineIndices+1] = charIndex
            lineWidths[#lineWidths+1] = lastLineWidth
            lineHeights[#lineHeights+1] = lastLineHeight
            spaceCounts[#spaceCounts+1] = lastLineSpaceCount
            symbolCounts[#symbolCounts+1] = lastLineSymbolCount
            textHeight = textHeight + lastLineHeight
        end
    end

    lineIndices[#lineIndices+1] = #chars
    lineWidths[#lineWidths+1] = currentLineWidth
    lineHeights[#lineHeights+1] = tallestLineChar
    spaceCounts[#spaceCounts+1] = currentSpaceCount
    symbolCounts[#symbolCounts+1] = currentSymbolCount
    textHeight = textHeight + tallestLineChar

    -- Edge case where the last line shouldn't exist at all
    -- (line is trying to start after the last character of the string)
    if lineIndices[#lineIndices-1] > lineIndices[#lineIndices] then
        lineIndices[#lineIndices] = nil
        lineIndices[#lineIndices] = nil
        lineWidths[#lineWidths] = nil
        lineHeights[#lineHeights] = nil
        spaceCounts[#spaceCounts] = nil
        symbolCounts[#symbolCounts] = nil
        textHeight = textHeight - tallestLineChar
    end

    ---@type Marker.WrapInfo
    local out = {
        lineIndices = lineIndices,
        lineWidths = lineWidths,
        lineHeights = lineHeights,
        textHeight = textHeight,
        spaceCounts = spaceCounts,
        symbolCounts = symbolCounts
    }

    return out
end

--- Checks if the given *MarkedText.chars[`charIndex`].effects[`effectIndex`]*
--- is the first char which that specific effect acts on.
---@param charIndex integer
---@param effectIndex integer
---@return boolean
function MarkedText:isEffectStartIndex(charIndex, effectIndex)
    local chars = self.chars

    local char = chars[charIndex]
    if not char.effects[effectIndex] then error("effectIndex '" .. tostring(effectIndex) .. "' isn't present in char", 2) end

    local charPrev = chars[charIndex-1]
    if not charPrev then return true end

    if charPrev.effects[effectIndex] ~= char.effects[effectIndex] then return true end
    return false
end

--- Checks if the given *MarkedText.chars[`charIndex`].effects[`effectIndex`]*
--- is the last char which that specific effect acts on.
---@param charIndex integer
---@param effectIndex integer
---@return boolean
function MarkedText:isEffectEndIndex(charIndex, effectIndex)
    local chars = self.chars

    local char = chars[charIndex]
    if not char.effects[effectIndex] then error("effectIndex '" .. tostring(effectIndex) .. "' isn't present in char", 2) end

    local charNext = chars[charIndex+1]
    if not charNext then return true end

    if charNext.effects[effectIndex] ~= char.effects[effectIndex] then return true end
    return false
end

--- Finds the index of the char which is the very last char under the
--- influence of the effect *MarkedText.chars[`charIndex`].effects[`effectIndex`]*
---@param charIndex integer
---@param effectIndex integer
---@return integer endCharIndex
function MarkedText:findEffectEndIndex(charIndex, effectIndex)
    local chars = self.chars

    local char = chars[charIndex]
    if not char.effects[effectIndex] then error("effectIndex '" .. tostring(effectIndex) .. "' isn't present in char", 2) end

    for nextCharIndex = charIndex, #chars do
        if self:isEffectEndIndex(nextCharIndex, effectIndex) then return nextCharIndex end
    end
    return #chars
end

-- MarkedChar --------------------------------------------------------------------------------------

--- Creates a new special MarkedChar
---@param str? string
---@param x? number
---@param y? number
---@param font? Marker.Font
---@return Marker.MarkedChar
function marker.newMarkedChar(str, x, y, font)
    -- new Marker.MarkedChar
    local markedChar = {
        str = str or "",
        xPlacement = x or 0,
        yPlacement = y or 0,
        font = font or marker.getDefaultFont(),
        colorR = marker.defaultColor[1],
        colorG = marker.defaultColor[2],
        colorB = marker.defaultColor[3],
        colorA = marker.defaultColor[4] or 1,
        xOffset = 0,
        yOffset = 0,
        disabled = false,
        effects = {},
    }
    return setmetatable(markedChar, MarkedCharMT)
end

---@return number
function MarkedChar:getWidth()
    return self.font:getWidth(self.str)
end

---@param includeLineHeight? boolean
---@return number
function MarkedChar:getHeight(includeLineHeight)
    return self.font:getHeight(includeLineHeight)
end

---@param nextChar Marker.MarkedChar
function MarkedChar:getKerning(nextChar)
    local fontA = self.font
    local fontB = nextChar.font
    local strA = self.str
    local strB = nextChar.str

    -- It's possible the fonts look identical (could be the same love font in there) or just have compatible kerning,
    -- but it's unlikely that a situation like that would even happen (why switch the font when it looks the same).
    if fontA ~= fontB then return 0 end

    return fontA:getKerning(strA, strB)
end

---@return boolean
function MarkedChar:isLineEnding()
    return self.str == "\n"
end

---@return boolean
function MarkedChar:isSpace()
    local str = self.str
    if str == " " then return true end -- just a regular space for now, will add nbsp and whatnot if it becomes necessary
    return false
end

--- Returns `true` if the character is (probably) a regular renderable character.
--- Returns `false` if it's an empty string or a common control character.
---@return boolean
function MarkedChar:isSymbol()
    local str = self.str
    if str == "" then return false end
    if str == "\a" then return false end
    if str == "\b" then return false end
    if str == "\t" then return false end
    if str == "\n" then return false end
    if str == "\v" then return false end
    if str == "\f" then return false end
    if str == "\r" then return false end
    return true
end

---@return boolean
function MarkedChar:isIdealWrapPoint()
    local str = self.str
    if str == " " then return true end
    return false
end

---@return boolean
function MarkedChar:isInvisibleInWrap()
    local str = self.str
    if str == " " then return true end
    return false
end

---@return boolean
function MarkedChar:isDisabled()
    return self.disabled
end

---@param x number
---@param y number
function MarkedChar:setPlacement(x, y)
    self.xPlacement = x
    self.yPlacement = y
end

--- Returns the attributes of the specified effect on the char, or `nil` if the effect isn't present on this char.
--- If the effect is applied multiple times on this char, each attribute will keep its most recently set value.
---@param effectName string
---@return table<string, string?>?
function MarkedChar:getEffectAttributes(effectName)
    local effects = self.effects
    local attributes

    for effectIndex = 1, #effects do
        local effectData = effects[effectIndex]
        if effectData.name == effectName then
            attributes = attributes or {}
            for key, value in pairs(effectData.attributes) do
                attributes[key] = value
            end
        end
    end

    return attributes
end

--- Resets the properties of the char
--- that only affect it visually but don't have an impact on how it's laid out.
--- 
--- This is called automatically each time effects are about to be applied.
function MarkedChar:resetVisuals()
    self.colorR = marker.defaultColor[1]
    self.colorG = marker.defaultColor[2]
    self.colorB = marker.defaultColor[3]
    self.colorA = marker.defaultColor[4] or 1
    self.renderedStr = nil
    self.xOffset = 0
    self.yOffset = 0
end

---@param x? number
---@param y? number
function MarkedChar:draw(x, y)
    if self:isDisabled() then return end

    x = x or 0
    y = y or 0

    local str = self.renderedStr or self.str

    local drawnX = math.floor(x + self.xPlacement + self.xOffset)
    local drawnY = math.floor(y + self.yPlacement + self.yOffset)

    local cr, cg, cb, ca = love.graphics.getColor()
    love.graphics.setColor(self.colorR, self.colorG, self.colorB, self.colorA)
    self.font:draw(str, drawnX, drawnY)
    love.graphics.setColor(cr, cg, cb, ca)
end

-- Effects -----------------------------------------------------------------------------------------

--- Creates a new effect object which can be registered as a valid effect for MarkedTexts to use.
---@return Marker.Effect
function marker.newEffect()
    -- new Marker.Effect
    local effect = {}
    return setmetatable(effect, EffectMT)
end

---@type table<string, Marker.Effect?>
marker.registeredEffects = {}

--- Registers an effect, making it usable in MarkedTexts.
---@param effectName string
---@param effect? Marker.Effect
---@return Marker.Effect
function marker.registerEffect(effectName, effect)
    effect = effect or marker.newEffect()
    marker.registeredEffects[effectName] = effect
    return effect
end

-----

marker.registerEffect("censor").charFn = function (char, attributes)
    local repl = attributes.repl or "*"

    if not char:isSymbol() then return "none" end
    if char:isSpace() then return "none" end
    if char.str == repl then return "none" end

    char.str = repl
    return "layout"
end

marker.registerEffect("color").charFn = function (char, attributes)
    local color = marker.getColor(attributes.value)
    char.colorR = color[1]
    char.colorG = color[2]
    char.colorB = color[3]
    char.colorA = color[4] or 1
end

marker.registerEffect("opacity").charFn = function (char, attributes)
    local value = tonumber(attributes.value) or 1
    char.colorA = char.colorA * value
end

marker.registerEffect("shake").charFn = function (char, attributes, info)
    local amount = (tonumber(attributes.amount) or 1) * 4
    local speed = (tonumber(attributes.speed) or 1) * 16

    local progress = math.floor(info.time * speed)

    local charSeed = 100 * info.charIndex + progress
    math.randomseed(charSeed)

    local xOffset = (math.random() - 0.5) * amount + 0.5
    local yOffset = (math.random() - 0.5) * amount + 0.5
    char.xOffset = char.xOffset + xOffset
    char.yOffset = char.yOffset + yOffset

    return "update"
end

marker.registerEffect("wiggle").charFn = function (char, attributes, info)
    local amount = (tonumber(attributes.amount) or 1) * 5
    local speed = (tonumber(attributes.speed) or 1) * 16

    local time = info.time
    local symbolIndex = info.symbolIndex or 0

    local progressFine = time * speed
    local progress = math.floor(progressFine)
    local progressFract = progressFine % 1

    local charSeed = symbolIndex + progress

    math.randomseed(charSeed)
    local xTarget = (math.random() - 0.5) * amount + 0.5
    local yTarget = (math.random() - 0.5) * amount + 0.5

    math.randomseed(charSeed-1)
    local xPrevious = (math.random() - 0.5) * amount + 0.5
    local yPrevious = (math.random() - 0.5) * amount + 0.5

    local t = (-math.pi/2) + (math.pi) * progressFract
    local interp = (math.sin(t)+1)/2

    local xOffset = xPrevious + (xTarget - xPrevious) * interp
    local yOffset = yPrevious + (yTarget - yPrevious) * interp
    char.xOffset = char.xOffset + xOffset
    char.yOffset = char.yOffset + yOffset

    return "update"
end

marker.registerEffect("wave").charFn = function (char, attributes, info)
    local amount = (tonumber(attributes.amount) or 1) * 5
    local speed = (tonumber(attributes.speed) or 1) * 10
    local wavelength = (tonumber(attributes.wavelength) or 1) * 2

    local time = info.time
    local symbolIndex = info.symbolIndex or 0

    if wavelength == 0 then return "update" end

    char.yOffset = char.yOffset + math.sin((time * speed) - (symbolIndex / wavelength)) * amount
    return "update"
end

marker.registerEffect("harmonica").charFn = function (char, attributes, info)
    local amount = (tonumber(attributes.amount) or 1) * 5
    local speed = (tonumber(attributes.speed) or 1) * 10
    local wavelength = (tonumber(attributes.wavelength) or 1) * 2

    local time = info.time
    local symbolIndex = info.symbolIndex or 0

    if wavelength == 0 then return "update" end

    char.xOffset = char.xOffset + math.sin((time * speed) - (symbolIndex / wavelength)) * amount
    return "update"
end

marker.registerEffect("corrupt").charFn = function (char, attributes, info)
    local speed = (tonumber(attributes.speed) or 1) * 20
    local chars = attributes.chars or "#$%&@=*?!"

    if not char:isSymbol() then return "update" end
    if char:isSpace() then return "update" end

    local charsLen = utf8.len(chars) or 0
    if charsLen == 0 then
        char.renderedStr = ""
        return "update"
    end

    local progress = math.floor(info.time * speed)
    local charSeed = 100 * info.charIndex + progress
    math.randomseed(charSeed)

    local pickedCharIndex = math.random(1, charsLen)
    char.renderedStr = string.sub(chars, utf8.offset(chars, pickedCharIndex), utf8.offset(chars, pickedCharIndex+1)-1)

    return "update"
end

marker.registerEffect("glue").stringFn = function (charView, attributes)
    local text = attributes.repl or attributes.text or charView:getContentsAsString()

    local contentsChanged = false
    for charIndex = 1, charView:getLength() do
        local char = charView:getChar(charIndex)
        local str = charIndex == 1 and text or ""

        contentsChanged = contentsChanged or (char.str ~= str)
        char.str = str
    end

    if contentsChanged then return "layout" end
end

marker.registerEffect("redact").stringFn = function (charView, attributes)
    local replacementText = attributes.text or "[REDACTED]"

    charView:replaceContents(replacementText)
end

marker.registerEffect("counter").stringFn = function (charView, attributes, info)
    local start = tonumber(attributes.start) or 0
    local speed = tonumber(attributes.speed) or 1
    local step = tonumber(attributes.step) or 1
    local loop = tonumber(attributes.loop) or nil

    local count = start + math.floor(info.time * speed) * step
    if loop then count = count % loop end

    charView:replaceContents(tostring(count))
    return "update"
end

marker.registerEffect("var").stringFn = function (charView, attributes, info)
    local ref = attributes.ref or ""

    local var = info.textVariables[ref]
    charView:replaceContents(tostring(var))
    return "update"
end

marker.registerEffect("typewriter").textFn = function (text)
    local time = text.time
    local timePrevious = text.timePrevious
    local chars = text.chars

    -- Delay the first character ever so slightly
    -- so it's still typed and isn't present at time=0
    local initialDelay = 1e-10
    time = time - initialDelay
    timePrevious = timePrevious - initialDelay

    local typingTime = 0

    for charIndex = 1, #chars do
        local char = chars[charIndex]
        local charStr = char.str
        local attributes = char:getEffectAttributes("typewriter")

        -- Collect attributes
        local delay = attributes and tonumber(attributes.delay) or 1
        local speed = attributes and tonumber(attributes.speed) or 1
        local fadein = attributes and marker.attributeToBool(attributes.fadein) or false
        local fadetime = attributes and tonumber(attributes.fadetime) or 1

        -- convert attributes to arbitrary better looking units + apply speed modifier
        delay = delay / 10
        delay = delay / speed

        -- Tweak delay based on character string
        if char:isSpace() or (not char:isSymbol()) then
            delay = 0
        end
        if charStr == "," or charStr == "." or charStr == ";" or charStr == ":" or charStr == "?" or charStr == "!" then
            delay = delay * 2.5
        end

        -- Special effects
        local charTypeProgress = (time - typingTime) / (delay * fadetime)
        charTypeProgress = math.min(math.max(charTypeProgress, 0), 1)

        if fadein then
            char.colorA = char.colorA * charTypeProgress
        end

        -- Type n stuff
        if attributes then
            if typingTime > time then
                char.renderedStr = ""
            elseif typingTime > timePrevious and marker.effectCallbacks.typewriter then
                marker.effectCallbacks.typewriter(char, attributes)
            end
            typingTime = typingTime + delay
        end
    end

    return "update"
end

-- CharView ----------------------------------------------------------------------------------------

--- Creates a new CharView for viewing and editing a range of characters in a MarkedChar array.
--- Used internally.
---@param chars Marker.MarkedChar[]
---@param indexFirst integer
---@param indexLast integer
---@return Marker.MarkedCharView
function marker.newMarkedCharView(chars, indexFirst, indexLast)
    local view = setmetatable({}, MarkedCharViewMT)
    view:_init(chars, indexFirst, indexLast)
    return view
end

--- (Re-)initializes the CharView. Used internally.
---@param chars Marker.MarkedChar[]
---@param indexFirst integer
---@param indexLast integer
function MarkedCharView:_init(chars, indexFirst, indexLast)
    self._chars = chars
    self._indexFirst = indexFirst
    self._indexLast = indexLast
    self._contentsWereReplaced = false
end

--- Returns the amount of chars in the view (aka the max viewable index)
---@return integer
function MarkedCharView:getLength()
    return self._indexLast - self._indexFirst + 1
end

--- Gets the char at the given (relative) index.
--- The index must be in the range between `1` and the return value of `getLength()`.
---@param index integer
---@return Marker.MarkedChar
function MarkedCharView:getChar(index)
    local indexReal = self._indexFirst + index - 1
    if indexReal < self._indexFirst or indexReal > self._indexLast then
        error("Attempting to index char outside of view", 2)
    end
    return self._chars[indexReal]
end

--- Returns `true` if `replaceContents()` was called on this view.
---@return boolean
function MarkedCharView:wereContentsReplaced()
    return self._contentsWereReplaced
end

--- Concatenates together the `str` of each char in the view and returns the resulting string.
---@return string
function MarkedCharView:getContentsAsString()
    local str = ""
    local chars = self._chars
    for charIndex = self._indexFirst, self._indexLast do
        str = str .. chars[charIndex].str
    end
    return str
end

--- Replaces the text (and clears any nested effects) of the chars in the view.
--- This may grow the view, but will never shrink it (extra chars will only ever be set to an empty string).
---@param newText string
function MarkedCharView:replaceContents(newText)
    local contentsChanged = false

    local indexFirst = self._indexFirst
    local indexLast = self._indexLast
    local chars = self._chars

    local nextIndex = indexFirst

    local newTextLen = utf8.len(newText)
    if not newTextLen then -- invalid utf8 string
        newText = ""
        newTextLen = 0
    end

    for pos, code in utf8.codes(newText) do
        local charStr = utf8.char(code)

        local char = chars[nextIndex]
        nextIndex = nextIndex + 1

        contentsChanged = contentsChanged or (char.str ~= charStr)
        char.str = charStr

        -- If we've run out of chars in view and need more, expand it by adding a char
        if nextIndex > indexLast and pos < newTextLen then
            contentsChanged = true

            local newChar = marker.newMarkedChar("", char.xPlacement, char.yPlacement, char.font)
            for effectIndex = 1, #char.effects do
                newChar.effects[effectIndex] = char.effects[effectIndex]
            end

            -- This one-by-one `table.insert`ing will be slow as hell but it won't happen every time,
            -- future calls will generally have the necessary amount of characters after growing once.
            table.insert(chars, nextIndex, newChar)
            indexLast = indexLast + 1
            self._indexLast = indexLast
        end
    end

    for clearedCharIndex = nextIndex, indexLast do
        local char = chars[clearedCharIndex]

        contentsChanged = contentsChanged or (char.str ~= "")
        char.str = ""
    end

    self._contentsWereReplaced = self._contentsWereReplaced or contentsChanged
end

-- Font stuff --------------------------------------------------------------------------------------

---@param str string
---@return integer
function AbstractFont:getWidth(str)
    return 0
end

---@param includeLineHeight? boolean
---@return number
function AbstractFont:getHeight(includeLineHeight)
    return 0
end

---@param leftChar string
---@param rightChar string
---@return number
function AbstractFont:getKerning(leftChar, rightChar)
    return 0
end

---@param str string
---@param x number
---@param y number
function AbstractFont:draw(str, x, y)
    return
end

for key, value in pairs(AbstractFont) do
    LoveFont[key] = value
end

----------

---@param font love.Font
function marker.newWrappedLoveFont(font)
    -- new Marker.LoveFont
    local markerLoveFont = {
        font = font
    }
    return setmetatable(markerLoveFont, LoveFontMT)
end

local defaultFont
---@return Marker.Font
function marker.getDefaultFont()
    defaultFont = defaultFont or marker.newWrappedLoveFont(love.graphics.getFont())
    return defaultFont
end

---@param str string
---@return number
function LoveFont:getWidth(str)
    return self.font:getWidth(str)
end

---@param includeLineHeight? boolean
---@return number
function LoveFont:getHeight(includeLineHeight)
    if includeLineHeight then return self.font:getHeight() * self.font:getLineHeight() end
    return self.font:getHeight()
end

---@param leftChar string
---@param rightChar string
---@return number
function LoveFont:getKerning(leftChar, rightChar)
    if leftChar == "" or rightChar == "" then return 0 end
    return self.font:getKerning(leftChar, rightChar)
end

---@param str string
---@param x number
---@param y number
function LoveFont:draw(str, x, y)
    love.graphics.print(str, self.font, x, y)
end

-- Parser ------------------------------------------------------------------------------------------

marker.parser = {}

marker.parser.allowedTagStartChars = {
    A = true, B = true, C = true, D = true,
    E = true, F = true, G = true, H = true,
    I = true, J = true, K = true, L = true,
    M = true, N = true, O = true, P = true,
    Q = true, R = true, S = true, T = true,
    U = true, V = true, W = true, X = true,
    Y = true, Z = true, a = true, b = true,
    c = true, d = true, e = true, f = true,
    g = true, h = true, i = true, j = true,
    k = true, l = true, m = true, n = true,
    o = true, p = true, q = true, r = true,
    s = true, t = true, u = true, v = true,
    w = true, x = true, y = true, z = true,
    ["_"] = true
}

marker.parser.allowedTagChars = {
    ["0"] = true,
    ["1"] = true,
    ["2"] = true,
    ["3"] = true,
    ["4"] = true,
    ["5"] = true,
    ["6"] = true,
    ["7"] = true,
    ["8"] = true,
    ["9"] = true,
    ["-"] = true,
    ["."] = true,
}
for key, value in pairs(marker.parser.allowedTagStartChars) do
    marker.parser.allowedTagChars[key] = marker.parser.allowedTagChars[key] or value
end

---@param arr any[]
local function clearArray(arr)
    for i = 1, #arr do arr[i] = nil end
end

--- Parses and processes all tags in the given sequence of MarkedChars
---@param markedChars Marker.MarkedChar[]
---@param tagStack? Marker.EffectData[]
---@return Marker.MarkedChar[]
function marker.parser.parse(markedChars, tagStack)
    return marker.parser.parse_text(markedChars, 1, {}, tagStack or {})
end

---@param markedChar Marker.MarkedChar
---@param tagStack Marker.EffectData[]
local function applyTagStackToMarkedChar(markedChar, tagStack)
    local effects = markedChar.effects
    clearArray(effects)

    for tagIndex = 1, #tagStack do
        effects[tagIndex] = tagStack[tagIndex]
    end
end

---@param charStr string
---@param markedChars Marker.MarkedChar[]
---@param markedCharsNew Marker.MarkedChar[]
---@param tagStack Marker.EffectData[]
local function appendNewCharToCharOutput(charStr, markedChars, markedCharsNew, tagStack)
    if not markedChars[1] then error("markedChars can't be empty") end
    local fillerChar = marker.newMarkedChar(charStr, 0, 0, markedChars[1].font)
    applyTagStackToMarkedChar(fillerChar, tagStack)
    markedCharsNew[#markedCharsNew+1] = fillerChar
end

---@param markedChars Marker.MarkedChar[]
---@param i integer
---@param markedCharsNew Marker.MarkedChar[]
---@param tagStack Marker.EffectData[]
---@return Marker.MarkedChar[]
function marker.parser.parse_text(markedChars, i, markedCharsNew, tagStack)
    while i <= #markedChars do
        local char = markedChars[i]
        local charStr = char.str

        if charStr == "<" then
            return marker.parser.parse_potentialTagStart(markedChars, i, markedCharsNew, tagStack)
        end

        if charStr == "&" then
            return marker.parser.parse_potentialCharacterEntity(markedChars, i, markedCharsNew, tagStack)
        end

        applyTagStackToMarkedChar(char, tagStack)
        markedCharsNew[#markedCharsNew+1] = char

        i = i + 1
    end
    return markedCharsNew
end

local definedCharacterEntities = {
    amp = "&",
    lt = "<",
    gt = ">",
    apos = "'",
    quot = '"',
}

---@param markedChars Marker.MarkedChar[]
---@param i integer
---@return integer i
---@return string? parsedEntity
local function parsePotentialCharacterEntity(markedChars, i)
    if i > #markedChars then return i end
    if markedChars[i].str ~= "&" then return i end

    local j = i + 1
    local entityCode = ""
    local formatIsValid = true
    while true do
        local char = markedChars[j]
        if not char then
            formatIsValid = false
            break
        end

        local charStr = char.str
        if charStr == " " or charStr == "\n" then
            formatIsValid = false
            break
        end

        if charStr == ";" then break end
        entityCode = entityCode .. charStr
        j = j + 1
    end

    if formatIsValid and definedCharacterEntities[entityCode] then
        return j+1, definedCharacterEntities[entityCode]
    end

    return i
end

---@param markedChars Marker.MarkedChar[]
---@param i integer
---@param markedCharsNew Marker.MarkedChar[]
---@param tagStack Marker.EffectData[]
---@return Marker.MarkedChar[]
function marker.parser.parse_potentialCharacterEntity(markedChars, i, markedCharsNew, tagStack)
    local parsedEntity
    i, parsedEntity = parsePotentialCharacterEntity(markedChars, i)

    if parsedEntity then
        appendNewCharToCharOutput(parsedEntity, markedChars, markedCharsNew, tagStack)
        return marker.parser.parse_text(markedChars, i, markedCharsNew, tagStack)
    end

    -- Not a valid character entity, ignore it
    applyTagStackToMarkedChar(markedChars[i], tagStack)
    markedCharsNew[#markedCharsNew+1] = markedChars[i]
    return marker.parser.parse_text(markedChars, i+1, markedCharsNew, tagStack)
end

---@param markedChars Marker.MarkedChar[]
---@param i integer
---@param markedCharsNew Marker.MarkedChar[]
---@param tagStack Marker.EffectData[]
---@return Marker.MarkedChar[]
function marker.parser.parse_potentialTagStart(markedChars, i, markedCharsNew, tagStack)
    if markedChars[i].str ~= "<" then error("Invalid tag opener") end

    if i >= #markedChars then
        markedCharsNew[#markedCharsNew+1] = markedChars[i]
        return markedCharsNew
    end

    i = i + 1

    local tagStart = markedChars[i].str
    if marker.parser.allowedTagStartChars[tagStart] then
        return marker.parser.parse_tag(markedChars, i, markedCharsNew, tagStack)
    end
    if tagStart == "/" then
        return marker.parser.parse_closingTag(markedChars, i, markedCharsNew, tagStack)
    end

    -- Not a tag, false alarm
    applyTagStackToMarkedChar(markedChars[i-1], tagStack)
    markedCharsNew[#markedCharsNew+1] = markedChars[i-1]
    return marker.parser.parse_text(markedChars, i, markedCharsNew, tagStack)
end

---@param markedChars Marker.MarkedChar[]
---@param i integer
---@return integer i
---@return string name
local function parseTagNameOrAttributeName(markedChars, i)
    local name = ""
    while true do
        local char = markedChars[i]
        if not char then break end

        local charStr = char.str
        if not marker.parser.allowedTagChars[charStr] then break end

        name = name .. charStr
        i = i + 1
    end
    return i, name
end

---@param markedChars Marker.MarkedChar[]
---@param i integer
---@return integer i
---@return string value
local function parseTagAttributeValue(markedChars, i)
    if i > #markedChars then return i, "" end

    local quoteChar = markedChars[i].str
    if not (quoteChar == "'" or quoteChar == '"') then return i, "" end

    i = i + 1

    local value = ""
    while true do
        local foundReplacementChar = false

        local char = markedChars[i]
        if not char then break end

        local charStr = char.str
        if charStr == quoteChar then break end

        if charStr == "&" then
            local parsedEntity
            i, parsedEntity = parsePotentialCharacterEntity(markedChars, i)
            if parsedEntity then
                value = value .. parsedEntity
                foundReplacementChar = true
            end
        end

        if not foundReplacementChar then
            value = value .. charStr
            i = i + 1
        end
    end

    return i, value
end

---@param markedChars Marker.MarkedChar[]
---@param i integer
---@return integer i
---@return string attributeName
---@return string attributeValue
local function parseTagAttribute(markedChars, i)
    local attributeName
    i, attributeName = parseTagNameOrAttributeName(markedChars, i)

    local equalsFound = false
    while true do
        local char = markedChars[i]
        if not char then break end

        local charStr = char.str

        if marker.parser.allowedTagStartChars[charStr] then break end
        if charStr == "/" or charStr == ">" then break end
        if charStr == "=" then equalsFound = true end

        if equalsFound and (charStr == "'" or charStr == '"') then
            local attributeValue
            i, attributeValue = parseTagAttributeValue(markedChars, i)

            return i, attributeName, attributeValue
        end

        i = i + 1
    end

    return i, attributeName, ""
end

---@param markedChars Marker.MarkedChar[]
---@param i integer
---@return integer i
---@return table<string, string> attributes
---@return boolean isSelfClosing
local function parseTagBody(markedChars, i)
    local attributes = {}
    local isSelfClosing = false
    while true do
        local char = markedChars[i]
        if not char then break end

        local charStr = char.str

        if charStr == "/" then isSelfClosing = true end
        if charStr == ">" then
            i = i + 1
            break
        end

        if marker.parser.allowedTagStartChars[charStr] then
            isSelfClosing = false

            local attributeName, attributeValue
            i, attributeName, attributeValue = parseTagAttribute(markedChars, i)
            attributes[attributeName] = attributeValue
        else
            i = i + 1
        end
    end
    return i, attributes, isSelfClosing
end

---@param markedChars Marker.MarkedChar[]
---@param i integer
---@param markedCharsNew Marker.MarkedChar[]
---@param tagStack Marker.EffectData[]
---@return Marker.MarkedChar[]
function marker.parser.parse_tag(markedChars, i, markedCharsNew, tagStack)
    if not marker.parser.allowedTagStartChars[markedChars[i].str] then error("Invalid tag start") end

    local tagName, tagAttributes, tagIsSelfClosing
    i, tagName = parseTagNameOrAttributeName(markedChars, i)
    i, tagAttributes, tagIsSelfClosing = parseTagBody(markedChars, i)

    tagStack[#tagStack+1] = {
        name = tagName,
        attributes = tagAttributes,
    }

    if tagIsSelfClosing then
        appendNewCharToCharOutput("", markedChars, markedCharsNew, tagStack)
        tagStack[#tagStack] = nil
    end

    if -- another tag (opening or closing) is flush with this one right after
        markedChars[i] and markedChars[i].str == "<"
        and markedChars[i+1] and (marker.parser.allowedTagStartChars[markedChars[i+1].str] or markedChars[i+1].str == "/")
    then
        appendNewCharToCharOutput("", markedChars, markedCharsNew, tagStack)
    end

    return marker.parser.parse_text(markedChars, i, markedCharsNew, tagStack)
end

---@param markedChars Marker.MarkedChar[]
---@param i integer
---@param markedCharsNew Marker.MarkedChar[]
---@param tagStack Marker.EffectData[]
---@return Marker.MarkedChar[]
function marker.parser.parse_closingTag(markedChars, i, markedCharsNew, tagStack)
    if markedChars[i].str ~= "/" then error("Invalid closing tag start") end

    local tagName
    i, tagName = parseTagNameOrAttributeName(markedChars, i+1)

    local tagStackTop = tagStack[#tagStack]
    if tagStackTop and tagStackTop.name == tagName then
        tagStack[#tagStack] = nil
    end

    while true do
        local char = markedChars[i]
        if not char then break end

        local charStr = char.str
        if charStr == ">" then
            i = i + 1
            break
        end

        i = i + 1
    end

    if -- another tag (opening or closing) is flush with this one right after
        markedChars[i] and markedChars[i].str == "<"
        and markedChars[i+1] and (marker.parser.allowedTagStartChars[markedChars[i+1].str] or markedChars[i+1].str == "/")
    then
        appendNewCharToCharOutput("", markedChars, markedCharsNew, tagStack)
    end

    return marker.parser.parse_text(markedChars, i, markedCharsNew, tagStack)
end

return marker