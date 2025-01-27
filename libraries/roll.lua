----------------------------------------------------------------------------------------------------
-- A wrapper for LÖVE's random generators
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

local roll = {}

--- This function is used internally to initially seed all new generators.  
--- Can be overwritten if you want to change the logic.
---@return number
function roll.getInitSeed()
    roll.initSeedOffset = roll.initSeedOffset + 1
    return os.time() + os.clock() * 1000 + roll.initSeedOffset
end
---@type number
roll.initSeedOffset = 0

-- Types -------------------------------------------------------------------------------------------

---@class Roll.RandomGenerator
---@field generator love.RandomGenerator The actual love generator to use for random functions
local RandomGenerator = {}
local RandomGeneratorMT = {__index = RandomGenerator}

-- Generators yipee --------------------------------------------------------------------------------

--- Creates a new random generator
---@return Roll.RandomGenerator
function roll.newRandomGenerator()
    -- new Roll.RandomGenerator
    local generator = {
        generator = love.math.newRandomGenerator()
    }
    generator.generator:setSeed(roll.getInitSeed())

    return setmetatable(generator, RandomGeneratorMT)
end

--- Returns a random number with the same arguments as `love.math.random()`.
---@param min integer
---@param max integer
---@return number
---@overload fun(self: Roll.RandomGenerator, max: integer): number
---@overload fun(self: Roll.RandomGenerator): number
function RandomGenerator:random(min, max)
    return self.generator:random(min, max)
end

RandomGeneratorMT.__call = function (self, min, max)
    return self:random(min, max)
end

--- Returns a random value from an array.
---@generic T
---@param list T[]
---@return T value
---@return integer index
function RandomGenerator:choose(list)
    local index = self:random(1, #list)
    return list[index], index
end

--- Returns a random value from an array weighted based on the weights in the second array.  
--- Weights of 0 can't get chosen, unless all weights are 0. Negative weights are considered 0.
--- ```lua
--- generator:chooseWeighted({"disallowed", "common", "common", "rare"}, {0, 1, 1, 0.25})
--- ```
---@generic T
---@param list T[]
---@param weights number[]
---@return T value
---@return integer index
function RandomGenerator:chooseWeighted(list, weights)
    if #list ~= #weights then error("List of weights must be the same length as the list of values", 2) end

    local weightSum = 0
    for weightIndex = 1, #weights do
        weightSum = weightSum + math.max(0, weights[weightIndex])
    end
    if weightSum == 0 then return self:choose(list) end

    local target = self:random() * weightSum
    for weightIndex = 1, #weights do
        local weight = math.max(0, weights[weightIndex])
        target = target - weight

        if target <= 0 and weight > 0 then
            return list[weightIndex], weightIndex
        end
    end
    return list[#list], #list
end

--- Shuffles the given array **in place**.
---@generic T
---@param list T[]
---@return T[]
function RandomGenerator:shuffle(list)
    for index = #list, 2, -1 do
        local swappedIndex = self:random(1, index)
        list[index], list[swappedIndex] = list[swappedIndex], list[index]
    end
    return list
end

--- Rolls a die with the given amount of faces.
---@param faces integer
---@return integer
function RandomGenerator:d(faces)
    return self:random(1, faces)
end

--- Rolls a six sided die.
---@return integer
function RandomGenerator:d6()
    return self:d(6)
end

--- Rolls a 20 sided die.
---@return integer
function RandomGenerator:d20()
    return self:d(20)
end

---@return integer low
---@return integer high
function RandomGenerator:getSeed()
    return self.generator:getSeed()
end

---@param low integer
---@param high integer
---@overload fun(self: Roll.RandomGenerator, seed: number)
function RandomGenerator:setSeed(low, high)
    if not high then return self.generator:setSeed(low) end
    return self.generator:setSeed(low, high)
end

---@return string
function RandomGenerator:getState()
    return self.generator:getState()
end

---@param state string
function RandomGenerator:setState(state)
    return self.generator:setState(state)
end


return roll