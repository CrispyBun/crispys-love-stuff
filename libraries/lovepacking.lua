----------------------------------------------------------------------------------------------------
-- A shrimple texture atlas packer for LÖVE,
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

local packing = {}

-- Packing algorithm based on: https://codeincomplete.com/articles/bin-packing/

-- Definitions -------------------------------------------------------------------------------------

---@alias Packing.InputTexturePaddingMode
---| '"none"' # The texture is not padded
---| '"grow"' # The sides of the texture are expanded by 1px

---@class Packing.InputTexture
---@field id string String ID to easily find the texture in the packed atlas later. Multiple textures can be grouped under the same ID, which is useful for animations (though make sure to define the order).
---@field order? number If grouping multiple textures by the same ID, this number determines their order. Nil is considered 0.
---@field texture love.Texture The texture to pack
---@field quad? love.Quad How to crop the texture before packing
---@field paddingMode Packing.InputTexturePaddingMode The way the texture is padded. Default is "grow" for all textures.
local InputTexture = {}
local InputTextureMT = {__index = InputTexture}

---@class Packing.PackedTexture
---@field atlas love.Texture The packed atlas the texture belongs to
---@field quad love.Quad The part of the packed atlas the texture is packed to

---@class Packing.PackingTree
---@field inputTextures Packing.InputTexture[] The textures to be packed into the atlas
---@field rootNode? Packing.PackingTreeNode
local PackingTree = {}
local PackingTreeMT = {__index = PackingTree}

---@class Packing.PackingTreeNode
---@field assignedTexture? Packing.InputTexture|true Either the assigned texture or simply true if it should be considered as assigned, even though there isn't actually a texture
---@field x number
---@field y number
---@field width number
---@field height number
---@field rightNode? Packing.PackingTreeNode
---@field bottomNode? Packing.PackingTreeNode
local PackingTreeNode = {}
local PackingTreeNodeMT = {__index = PackingTreeNode}

-- Input texture preparation -----------------------------------------------------------------------

--- Creates a new input texture to be used in a `PackingTree`.
---@param id string The ID to find the texture by later. Multiple textures can be associated with the same ID.
---@param texture love.Texture The texture to pack
---@param quad? love.Quad Optional quad to crop the texture before packing
---@param order? number Optional value to determine the order of the texture relative to other textures grouped by the same ID
---@return Packing.InputTexture
function packing.newInputTexture(id, texture, quad, order)
    -- new Packing.InputTexture
    local input = {
        id = id,
        texture = texture,
        quad = quad,
        order = order,
        paddingMode = "grow"
    }
    return setmetatable(input, InputTextureMT)
end

--- Creates a new array of input textures from a texture and an array of quads, setting the textures' order to be in the same order as the quads after packing.
---@param id string The ID to find the textures by later
---@param texture love.Texture The texture of the spritesheet
---@param quads love.Quad[] The quads defining the frames of the animation
---@return Packing.InputTexture[]
function packing.newInputSpritesheet(id, texture, quads)
    ---@type Packing.InputTexture[]
    local inputs = {}
    for quadIndex = 1, #quads do
        inputs[#inputs+1] = packing.newInputTexture(id, texture, quads[quadIndex], quadIndex)
    end
    return inputs
end

--- Returns the dimensions the texture will take up on the packed atlas. Takes into account the quad and padding.
---@return number width
---@return number height
function InputTexture:getDimensions()
    local width, height = self:getDimensionsPaddingless()

    local paddingMode = self.paddingMode

    if paddingMode == "none" then
        return width, height
    end

    if paddingMode == "grow" then
        return width+2, height+2
    end

    error("Unknown padding mode: " .. tostring(paddingMode))
end

--- Returns the width and height of the texture, without taking padding into account.
--- The optional quad *is* taken into account.
---@return number width
---@return number height
function InputTexture:getDimensionsPaddingless()
    local width, height = self.texture:getDimensions()
    if self.quad then _, _, width, height = self.quad:getViewport() end
    return width, height
end

--- Draws the input texture as it will be drawn onto the packed atlas.
---@param x number
---@param y number
function InputTexture:draw(x, y)
    local paddingMode = self.paddingMode

    if paddingMode == "none" then
        self:drawPaddingless(x, y)
        return
    end

    if paddingMode == "grow" then
        local width, height = self:getDimensionsPaddingless()
        local sx, sy, sw, sh = love.graphics.getScissor()

        -- Top-left corner pixel
        love.graphics.setScissor(x, y, 1, 1)
        self:drawPaddingless(x, y)

        -- Top-right corner pixel
        love.graphics.setScissor(x+width+1, y, 1, 1)
        self:drawPaddingless(x+2, y)

        -- Bottom-left corner pixel
        love.graphics.setScissor(x, y+height+1, 1, 1)
        self:drawPaddingless(x, y+2)

        -- Bottom-right corner pixel
        love.graphics.setScissor(x+width+1, y+height+1, 1, 1)
        self:drawPaddingless(x+2, y+2)

        -- Top pixel row
        love.graphics.setScissor(x+1, y, width, 1)
        self:drawPaddingless(x+1, y)

        -- Left pixel column
        love.graphics.setScissor(x, y+1, 1, height)
        self:drawPaddingless(x, y+1)

        -- Right pixel column
        love.graphics.setScissor(x+width+1, y+1, 1, height)
        self:drawPaddingless(x+2, y+1)

        -- Bottom pixel row
        love.graphics.setScissor(x+1, y+width+1, width, 1)
        self:drawPaddingless(x+1,y+2)

        -- Actual image in the middle
        love.graphics.setScissor(x+1, y+1, width, height)
        self:drawPaddingless(x+1, y+1)

        love.graphics.setScissor(sx, sy, sw, sh) -- reset scissor
        return
    end

    error("Unknown padding mode: " .. tostring(paddingMode))
end

--- Similar to `InputTexture:draw()`, but always draws as if the padding mode is set to `"none"`.
---@param x number
---@param y number
function InputTexture:drawPaddingless(x, y)
    if self.quad then
        love.graphics.draw(self.texture, self.quad, x, y)
    else
        love.graphics.draw(self.texture, x, y)
    end
end

-- The packing tree --------------------------------------------------------------------------------

--- Creates a new packing tree for creating a texture atlas.
---@return Packing.PackingTree
function packing.newPackingTree()
    -- new Packing.PackingTree
    local tree = {
        inputTextures = {}
    }
    return setmetatable(tree, PackingTreeMT)
end

--- Adds an input texture to the tree.
---@param inputTexture Packing.InputTexture
---@return self self
function PackingTree:addInputTexture(inputTexture)
    self.inputTextures[#self.inputTextures+1] = inputTexture
    return self
end

--- Creates and adds a new input texture to the tree.
---@param id string The ID to find the texture by later. Multiple textures can be associated with the same ID.
---@param texture love.Texture The texture to pack
---@param quad? love.Quad Optional quad to crop the texture before packing
---@param order? number Optional value to determine the order of the texture relative to other textures grouped by the same ID
---@return self self
function PackingTree:addNewInputTexture(id, texture, quad, order)
    local input = packing.newInputTexture(id, texture, quad, order)
    return self:addInputTexture(input)
end

--- Adds an array of input textures to the tree.
---@param inputTextures any
---@return Packing.PackingTree
function PackingTree:addInputTextures(inputTextures)
    for inputIndex = 1, #inputTextures do
        self:addInputTexture(inputTextures[inputIndex])
    end
    return self
end

--- Deletes all the calculated nodes of the tree.
function PackingTree:clear()
    self.rootNode = nil
end

---@param a Packing.InputTexture
---@param b Packing.InputTexture
local function compareInputTextures(a, b)
    local aWidth, aHeight = a:getDimensions()
    local bWidth, bHeight = b:getDimensions()

    local maxSideA = math.max(aWidth, aHeight)
    local maxSideB = math.max(bWidth, bHeight)
    if maxSideA ~= maxSideB then return maxSideA > maxSideB end

    local areaA = aWidth * aHeight
    local areaB = bWidth * bHeight
    if areaA ~= areaB then return areaA > areaB end

    if aHeight ~= bHeight then return aHeight > bHeight end
    if aWidth ~= bWidth then return aWidth > bWidth end

    return false
end

--- Generates the tree of packed textures.
function PackingTree:pack()
    self:clear()

    local inputTextures = self.inputTextures
    table.sort(inputTextures, compareInputTextures)

    if #inputTextures == 0 then return end

    for textureIndex = 1, #inputTextures do
        local texture = inputTextures[textureIndex]
        self:injectTexture(texture)
    end
end
PackingTree.calulate = PackingTree.pack

--- Injects a texture into the first node it fits into. Used internally.  
--- To add textures to be packed, use `PackingTree:addInputTexture()` instead.
--- 
--- The textures should be inserted after being sorted properly largest to smallest, otherwise this might fail.
---@param texture Packing.InputTexture
function PackingTree:injectTexture(texture)
    if not self.rootNode then
        local textureWidth, textureHeight = texture:getDimensions()
        self.rootNode = packing.newPackingTreeNode(0, 0, textureWidth, textureHeight)
        self.rootNode:assignTexture(texture)
        return self.rootNode
    end

    local success = self.rootNode:injectTexture(texture)
    if not success then
        local newNode = self:growRootNode(texture:getDimensions())
        local guaranteedSuccess = newNode:injectTexture(texture)
        if not guaranteedSuccess then
            error("???")
        end
    end
end

--- Used internally.
---@param addedAreaWidth number
---@param addedAreaHeight number
---@return Packing.PackingTreeNode newAreaNode
function PackingTree:growRootNode(addedAreaWidth, addedAreaHeight)
    local rootNode = self.rootNode
    if not rootNode then
        error("Can't grow root node - no root node exists", 2)
    end

    local x, y, width, height = rootNode:getBounds()

    local canGrowRight = addedAreaHeight <= height
    local canGrowDown = addedAreaWidth <= width
    if not (canGrowRight or canGrowDown) then
        -- this should be impossible to trigger as long as the textures are sorted by size
        -- and the node is grown only by progressively smaller sizes
        error("Attempting to grow node in both directions at the same time", 2)
    end

    local rightGrownWidth = width + addedAreaWidth
    local downGrownHeight = height + addedAreaHeight

    local growRight = canGrowRight
    if growRight and canGrowDown then
        local rightGrownSideDifference = math.abs(rightGrownWidth - height)
        local downGrownSideDifference = math.abs(width - downGrownHeight)
        local growingRightMakesBetterSquare = rightGrownSideDifference < downGrownSideDifference

        if not growingRightMakesBetterSquare then
            growRight = false
        end
    end

    if growRight then
        local newRootNode = packing.newPackingTreeNode(x, y, rightGrownWidth, height)
        newRootNode.assignedTexture = true
        newRootNode.rightNode = packing.newPackingTreeNode(x + width, y, addedAreaWidth, height)
        newRootNode.bottomNode = rootNode
        self.rootNode = newRootNode
        return self.rootNode.rightNode
    end

    local newRootNode = packing.newPackingTreeNode(x, y, width, downGrownHeight)
    newRootNode.assignedTexture = true
    newRootNode.rightNode = rootNode
    newRootNode.bottomNode = packing.newPackingTreeNode(x, y + height, width, addedAreaHeight)
    self.rootNode = newRootNode
    return self.rootNode.bottomNode
end

-- Nodes of the tree -------------------------------------------------------------------------------

--- Creates a new packing tree node. Used internally.
---@param x? number
---@param y? number
---@param width? number
---@param height? number
---@return Packing.PackingTreeNode
function packing.newPackingTreeNode(x, y, width, height)
    -- new Packing.PackingTreeNode
    local node = {
        x = x or 0,
        y = y or 0,
        width = width or 0,
        height = height or 0
    }
    return setmetatable(node, PackingTreeNodeMT)
end

--- Injects a texture to the first free node it finds for (if any) it and splits the node accordingly.
---@param texture Packing.InputTexture
---@return Packing.PackingTreeNode? usedNode
function PackingTreeNode:injectTexture(texture)
    -- if the node is already used up, forward the inject to any neighboring nodes
    if self.assignedTexture then
        ---@type Packing.PackingTreeNode?
        local foundNode
        if self.rightNode then
            foundNode = self.rightNode:injectTexture(texture)
        end
        if not foundNode and self.bottomNode then
            foundNode = self.bottomNode:injectTexture(texture)
        end
        return foundNode
    end

    local textureWidth, textureHeight = texture:getDimensions()
    local nodeWidth, nodeHeight = self:getDimensions()

    -- Technically we could try to forward to neighbor nodes here,
    -- but it's safe to assume all further nodes in the tree will be too small as well
    if textureWidth > nodeWidth then return nil end
    if textureHeight > nodeHeight then return nil end

    self:assignTexture(texture)
    self:split(textureWidth, textureHeight)
    return self
end

--- Gives the node a new size and creates a `rightNode` and a `bottomNode` to fill in its previous space.
---@param newWidth number
---@param newHeight number
function PackingTreeNode:split(newWidth, newHeight)
    if self.rightNode or self.bottomNode then
        error("Can't split node which already has neighbor nodes", 2)
    end

    local x, y, width, height = self:getBounds()
    if newWidth > width or newHeight > height then
        error("Can't split node to be a greater size than it already is", 2)
    end

    self.rightNode = packing.newPackingTreeNode(x+newWidth, y, width-newWidth, newHeight)
    self.bottomNode = packing.newPackingTreeNode(x, y+newHeight, width, height-newHeight)
    self:setSize(newWidth, newHeight)
end

---@param texture Packing.InputTexture
function PackingTreeNode:assignTexture(texture)
    self.assignedTexture = texture
end

---@return number x
---@return number y
---@return number width
---@return number height
function PackingTreeNode:getBounds()
    return self.x, self.y, self.width, self.height
end

---@return number width
---@return number height
function PackingTreeNode:getDimensions()
    return self.width, self.height
end

---@param width number
---@param height number
---@return self
function PackingTreeNode:setSize(width, height)
    self.width = width
    self.height = height
    return self
end

return packing