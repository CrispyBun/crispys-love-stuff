----------------------------------------------------------------------------------------------------
-- A simple (yet very messy) LÖVE 9-slicing
-- written by yours truly, CrispyBun.
-- crispybun@pm.me
----------------------------------------------------------------------------------------------------
--[[
MIT License

Copyright (c) 2026 Ava "CrispyBun" Špráchalů

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

local slice = {}

---@class Slice.SlicedTexture
---@field texture love.Texture
---@field quadTL love.Quad
---@field quadT love.Quad
---@field quadTR love.Quad
---@field quadR love.Quad
---@field quadBR love.Quad
---@field quadB love.Quad
---@field quadBL love.Quad
---@field quadL love.Quad
---@field quadC love.Quad
local SlicedTexture = {}
local SlicedTextureMT = {__index = SlicedTexture}

---@class Slice.BatchedSlicedTexture
---@field slicedTexture Slice.SlicedTexture
---@field spriteBatch love.SpriteBatch
---@field extraQuads love.Quad[]
---@field nextExtraQuadIndex integer
---@field x number
---@field y number
---@field width number
---@field height number
---@field textureScale? number
local BatchedSlicedTexture = {}
local BatchedSlicedTextureMT = {__index = BatchedSlicedTexture}

--------------------------------

--- Creates a new sliced texture from 1 texture (where the full texture is the rectangle to be 9-sliced)
--- and the sizes of the top-left and bottom-right corners (the sizes of the other slices will be inferred from those).
---@param texture love.Texture
---@param topLeftWidth number
---@param topLeftHeight number
---@param bottomRightWidth number
---@param bottomRightHeight number
---@return Slice.SlicedTexture
function slice.newSlicedTexture(texture, topLeftWidth, topLeftHeight, bottomRightWidth, bottomRightHeight)
    local textureWidth, textureHeight = texture:getDimensions()

    local centerWidth = textureWidth - topLeftWidth - bottomRightWidth
    local centerHeight = textureHeight - topLeftHeight - bottomRightHeight

    if topLeftWidth + bottomRightWidth >= textureWidth then error("topLeftWidth and bottomRightWidth summed must be less than texture width", 2) end
    if topLeftHeight + bottomRightHeight >= textureHeight then error("topLeftHeight and bottomRightHeight summed must be less than texture height", 2) end

    local quadTL = love.graphics.newQuad(0, 0, topLeftWidth, topLeftHeight, texture)
    local quadT = love.graphics.newQuad(topLeftWidth, 0, centerWidth, topLeftHeight, texture)
    local quadTR = love.graphics.newQuad(topLeftWidth + centerWidth, 0, bottomRightWidth, topLeftHeight, texture)
    local quadR = love.graphics.newQuad(topLeftWidth + centerWidth, topLeftHeight, bottomRightWidth, centerHeight, texture)
    local quadBR = love.graphics.newQuad(topLeftWidth + centerWidth, topLeftHeight + centerHeight, bottomRightWidth, bottomRightHeight, texture)
    local quadB = love.graphics.newQuad(topLeftWidth, topLeftHeight + centerHeight, centerWidth, bottomRightHeight, texture)
    local quadBL = love.graphics.newQuad(0, topLeftHeight + centerHeight, topLeftWidth, bottomRightHeight, texture)
    local quadL = love.graphics.newQuad(0, topLeftHeight, topLeftWidth, centerHeight, texture)
    local quadC = love.graphics.newQuad(topLeftWidth, topLeftHeight, centerWidth, centerHeight, texture)

    return slice.newSlicedTextureFromQuads(texture, quadTL, quadT, quadTR, quadR, quadBR, quadB, quadBL, quadL, quadC)
end

--- Creates a new sliced texture from a texture (can be a texture atlas)
--- and each of the 9 slices given as quads (in clockwise order, with the center one being last).
---@param texture love.Texture
---@param topLeftQuad love.Quad
---@param topQuad love.Quad
---@param topRightQuad love.Quad
---@param rightQuad love.Quad
---@param bottomRightQuad love.Quad
---@param bottomQuad love.Quad
---@param bottomLeftQuad love.Quad
---@param leftQuad love.Quad
---@param centerQuad love.Quad
---@return Slice.SlicedTexture
function slice.newSlicedTextureFromQuads(texture, topLeftQuad, topQuad, topRightQuad, rightQuad, bottomRightQuad, bottomQuad, bottomLeftQuad, leftQuad, centerQuad)
    ---@type Slice.SlicedTexture
    local sliced = {
        texture = texture,
        quadTL = topLeftQuad,
        quadT = topQuad,
        quadTR = topRightQuad,
        quadR = rightQuad,
        quadBR = bottomRightQuad,
        quadB = bottomQuad,
        quadBL = bottomLeftQuad,
        quadL = leftQuad,
        quadC = centerQuad,
    }
    return setmetatable(sliced, SlicedTextureMT)
end

--------------------------------

--- Creates a new BatchedSlicedTexture instance from this SlicedTexture
--- which batches the quads and sprites for much faster drawing (even more so if drawn with the same parameters over and over).
---@param spriteBatchUsage? love.SpriteBatchUsage
function SlicedTexture:makeBatched(spriteBatchUsage)
    ---@type Slice.BatchedSlicedTexture
    local batched = {
        slicedTexture = self,
        spriteBatch = love.graphics.newSpriteBatch(self.texture, 1000, spriteBatchUsage or "static"),
        extraQuads = {},
        nextExtraQuadIndex = 1,
        x = 0,
        y = 0,
        width = 0,
        height = 0,
        textureScale = 0
    }
    return setmetatable(batched, BatchedSlicedTextureMT)
end

---@param x number
---@param y number
---@param width number
---@param height number
---@param textureScale? number
---@param _batchedInstance? Slice.BatchedSlicedTexture
function SlicedTexture:draw(x, y, width, height, textureScale, _batchedInstance)
    textureScale = textureScale or 1

    local _, _, topLeftWidth, topLeftHeight = self.quadTL:getViewport()
    local _, _, bottomRightWidth, bottomRightHeight = self.quadBR:getViewport()
    topLeftWidth = topLeftWidth * textureScale
    topLeftHeight = topLeftHeight * textureScale
    bottomRightWidth = bottomRightWidth * textureScale
    bottomRightHeight = bottomRightHeight * textureScale

    local _, _, centerWidth, centerHeight = self.quadC:getViewport()
    centerWidth = centerWidth * textureScale
    centerHeight = centerHeight * textureScale

    local minWidth = topLeftWidth + bottomRightWidth
    local minHeight = topLeftHeight + bottomRightHeight
    if width < minWidth then x = x - math.floor((minWidth - width) / 2 + 0.5) end
    if height < minHeight then y = y - math.floor((minHeight - height) / 2 + 0.5) end
    width = math.max(width, minWidth)
    height = math.max(height, minHeight)

    local texture = self.texture
    if _batchedInstance then _batchedInstance.spriteBatch:clear() end
    local textureOrBatchedInstance = _batchedInstance or texture

    -- excuse how awfully ugly this is lol

    -- Corners
    self:drawPart(textureOrBatchedInstance, self.quadTL, x, y, textureScale)
    self:drawPart(textureOrBatchedInstance, self.quadTR, x + width - bottomRightWidth, y, textureScale)
    self:drawPart(textureOrBatchedInstance, self.quadBR, x + width - bottomRightWidth, y + height - bottomRightHeight, textureScale)
    self:drawPart(textureOrBatchedInstance, self.quadBL, x, y + height - bottomRightHeight, textureScale)

    -- Top + bottom
    local horizontalProgress = x + topLeftWidth
    local horizontalRemaining = width - topLeftWidth - bottomRightWidth
    while horizontalRemaining > 0 do
        local scissorX, scissorY, scissorW, scissorH
        if centerWidth > horizontalRemaining then
            scissorX = horizontalProgress
            scissorY = y
            scissorW = horizontalRemaining
            scissorH = height
        end

        self:drawPart(textureOrBatchedInstance, self.quadT, horizontalProgress, y, textureScale, scissorX, scissorY, scissorW, scissorH)
        self:drawPart(textureOrBatchedInstance, self.quadB, horizontalProgress, y + height - bottomRightHeight, textureScale, scissorX, scissorY, scissorW, scissorH)
        horizontalProgress = horizontalProgress + centerWidth
        horizontalRemaining = horizontalRemaining - centerWidth
    end

    -- Left + right
    local verticalProgress = y + topLeftHeight
    local verticalRemaining = height - topLeftHeight - bottomRightHeight
    while verticalRemaining > 0 do
        local scissorX, scissorY, scissorW, scissorH
        if centerHeight > verticalRemaining then
            scissorX = x
            scissorY = verticalProgress
            scissorW = width
            scissorH = verticalRemaining
        end

        self:drawPart(textureOrBatchedInstance, self.quadL, x, verticalProgress, textureScale, scissorX, scissorY, scissorW, scissorH)
        self:drawPart(textureOrBatchedInstance, self.quadR, x + width - bottomRightWidth, verticalProgress, textureScale, scissorX, scissorY, scissorW, scissorH)
        verticalProgress = verticalProgress + centerHeight
        verticalRemaining = verticalRemaining - centerHeight
    end

    -- Center
    horizontalProgress = x + topLeftWidth
    horizontalRemaining = width - topLeftWidth - bottomRightWidth
    while horizontalRemaining > 0 do
        verticalProgress = y + topLeftHeight
        verticalRemaining = height - topLeftHeight - bottomRightHeight
        while verticalRemaining > 0 do
            local scissorX, scissorY, scissorW, scissorH
            if centerWidth > horizontalRemaining or centerHeight > verticalRemaining then
                scissorX = horizontalProgress
                scissorY = verticalProgress
                scissorW = horizontalRemaining
                scissorH = verticalRemaining
            end

            self:drawPart(textureOrBatchedInstance, self.quadC, horizontalProgress, verticalProgress, textureScale, scissorX, scissorY, scissorW, scissorH)
            verticalProgress = verticalProgress + centerHeight
            verticalRemaining = verticalRemaining - centerHeight
        end
        horizontalProgress = horizontalProgress + centerWidth
        horizontalRemaining = horizontalRemaining - centerWidth
    end

    if _batchedInstance then love.graphics.draw(_batchedInstance.spriteBatch) end
end

local function intersectViewports(x1, y1, w1, h1, x2, y2, w2, h2)
    local xStart = math.max(x1, x2)
    local yStart = math.max(y1, y2)
    local xEnd = math.min(x1 + w1, x2 + w2)
    local yEnd = math.min(y1 + h1, y2 + h2)
    return xStart, yStart, xEnd - xStart, yEnd - yStart
end

---@package
---@param textureOrBatchedInstance love.Texture|Slice.BatchedSlicedTexture
---@param quad love.Quad
---@param x number
---@param y number
---@param scale number
---@param scissorX? number
---@param scissorY? number
---@param scissorW? number
---@param scissorH? number
function SlicedTexture:drawPart(textureOrBatchedInstance, quad, x, y, scale, scissorX, scissorY, scissorW, scissorH)
    if type(textureOrBatchedInstance) == "table" then
        local extraQuad
        if scissorX and scissorY and scissorW and scissorH then
            local quadX, quadY, quadW, quadH = quad:getViewport()
            quadW = quadW * scale
            quadH = quadH * scale
            local newQuadX, newQuadY, newQuadW, newQuadH = intersectViewports(scissorX - x + quadX, scissorY - y + quadY, scissorW, scissorH, quadX, quadY, quadW, quadH)
            newQuadW = newQuadW / scale
            newQuadH = newQuadH / scale
            extraQuad = textureOrBatchedInstance:getExtraQuad(newQuadX, newQuadY, newQuadW, newQuadH)
        end
        textureOrBatchedInstance.spriteBatch:add(extraQuad or quad, x, y, 0, scale, scale)
    else
        local sx, sy, sw, sh = love.graphics.getScissor()
        if scissorX and scissorY and scissorW and scissorH then
            love.graphics.setScissor(scissorX, scissorY, scissorW, scissorH)
        end
        love.graphics.draw(textureOrBatchedInstance--[[@as love.Texture]], quad, x, y, 0, scale, scale)
        love.graphics.setScissor(sx, sy, sw, sh)
    end
end

--------------------------------

---@param x number
---@param y number
---@param width number
---@param height number
---@param textureScale? number
function BatchedSlicedTexture:draw(x, y, width, height, textureScale)
    if  x == self.x and
        y == self.y and
        width == self.width and
        height == self.height and
        textureScale == self.textureScale
    then
        love.graphics.draw(self.spriteBatch)
        return
    end

    self.nextExtraQuadIndex = 1

    self.x = x
    self.y = y
    self.width = width
    self.height = height
    self.textureScale = textureScale

    return self.slicedTexture:draw(x, y, width, height, textureScale, self)
end

---@package
---@param x number
---@param y number
---@param width number
---@param height number
---@return love.Quad
function BatchedSlicedTexture:getExtraQuad(x, y, width, height)
    local nextIndex = self.nextExtraQuadIndex
    local quads = self.extraQuads
    self.nextExtraQuadIndex = self.nextExtraQuadIndex + 1

    if quads[nextIndex] then
        quads[nextIndex]:setViewport(x, y, width, height, self.slicedTexture.texture:getDimensions())
        return quads[nextIndex]
    end

    quads[nextIndex] = love.graphics.newQuad(x, y, width, height, self.slicedTexture.texture)
    return quads[nextIndex]
end

return slice