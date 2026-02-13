----------------------------------------------------------------------------------------------------
-- A neat sfx and music manager for LÖVE,
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

local sounding = {}

--- This can be replaced to make the library use a different function for randomization
--- (the function should behave the same way as the regular math.random function)
---@type function
sounding.randomFn = math.random

-- Definitions -------------------------------------------------------------------------------------

--- The shared interface for all types of sounds and music
---@class Sounding.Audio
local Audio = {}

--- Options that various `Sounding.Audio` implementations may or may not pay attention to
---@class Sounding.AudioOptions

--- A basic sound effect
---@class Sounding.Sound : Sounding.Audio
---@field baseSource love.Source
---@field sources love.Source[]
---@field nextFreeSource integer
---@field maxSources integer
---@field basePitch number
---@field randomPitchScale number
local Sound = {}
local SoundMT = {__index = Sound}

--- A sound effect that picks from a couple of sounds to play
---@class Sounding.RandomizedSound : Sounding.Audio
---@field sounds Sounding.Audio[]
local RandomizedSound = {}
local RandomizedSoundMT = {__index = RandomizedSound}

-- Main interface ----------------------------------------------------------------------------------

---@param soundId string
function sounding.play(soundId)
    error("NYI")
end

-- Sounds ------------------------------------------------------------------------------------------

--- Creates a new SFX. Should be made from a static source.
---@param source love.Source
---@return Sounding.Sound
function sounding.newSound(source)
    ---@type Sounding.Sound
    local sound = {
        baseSource = source,
        sources = {},
        nextFreeSource = 1,
        maxSources = 5,
        basePitch = 1,
        randomPitchScale = 1,
    }
    return setmetatable(sound, SoundMT)
end

---@param options? Sounding.AudioOptions
---@return integer sourceIndex
function Sound:play(options)
    local sources = self.sources

    local nextFreeSource = self.nextFreeSource
    local maxSources = self.maxSources

    if nextFreeSource > maxSources then nextFreeSource = 1 end
    if not sources[nextFreeSource] then
        sources[nextFreeSource] = self.baseSource:clone()
    end

    local source = sources[nextFreeSource]

    source:setPitch(self:generatePitch())

    source:stop()
    source:play()

    self.nextFreeSource = nextFreeSource + 1
    return nextFreeSource
end

function Sound:stopAll()
    local sources = self.sources

    for sourceIndex = 1, self.maxSources do
        local source = sources[sourceIndex]
        if source then source:stop() end
    end
end

---@param id integer
---@return love.Source
function Sound:readId(id)
    return self.sources[id]
end

--- Sets how many clones of the base source can be created for this sfx at most
---@param maxSources integer
function Sound:setMaxSources(maxSources)
    for sourceIndex = maxSources + 1, self.maxSources, 1 do
        self.sources[sourceIndex] = nil
    end

    self.maxSources = maxSources
end

--- Creates all the source clones in advance
function Sound:populateMaxSources()
    local baseSource = self.baseSource
    local sources = self.sources

    for sourceIndex = 1, self.maxSources do
        sources[sourceIndex] = baseSource:clone()
    end

    self.nextFreeSource = 1
end

---@param pitch number
---@return self
function Sound:setBasePitch(pitch)
    if pitch <= 0 then error("Invalid pitch", 2) end
    self.basePitch = pitch
    return self
end

--- Sets by how much the sound pitch sould change each time it's played
---@param randomPitchScale number
---@return self
function Sound:setRandomPitchScale(randomPitchScale)
    if randomPitchScale < 1 then error("Invalid pitch scale", 2) end
    self.randomPitchScale = randomPitchScale
    return self
end

---@private
---@return number
function Sound:generatePitch()
    local pitch = self.basePitch
    local randomPitchScale = self.randomPitchScale

    local pitchMin = pitch / randomPitchScale
    local pitchMax = pitch * randomPitchScale

    return pitchMin + sounding.randomFn() * (pitchMax - pitchMin)
end

--------------------------------------------------

--- Creates a new sound for playing randomly from a set of different `Sounding.Audio`s.
---@param ... Sounding.Audio
---@return Sounding.RandomizedSound
function sounding.newRandomizedSound(...)
    ---@type Sounding.RandomizedSound
    local sound = {
        sounds = {...}
    }
    return setmetatable(sound, RandomizedSoundMT)
end

---@param options? Sounding.AudioOptions
---@return integer soundIndex
function RandomizedSound:play(options)
    local sounds = self.sounds
    local soundIndex = sounding.randomFn(#sounds)

    sounds[soundIndex]:play(options)
    return soundIndex
end

function RandomizedSound:stopAll()
    local sounds = self.sounds
    for soundIndex = 1, #sounds do
        sounds[soundIndex]:stopAll()
    end
end

---@param id integer
---@return Sounding.Audio
function RandomizedSound:readId(id)
    return self.sounds[id]
end

---@param sound Sounding.Audio
function RandomizedSound:addSoundOption(sound)
    self.sounds[#self.sounds+1] = sound
end

-- The abstract shared Audio interface -------------------------------------------------------------

--- Plays the audio and returns some sort of identifier for it
---@param options? Sounding.AudioOptions
---@return integer id
function Audio:play(options)
    return 0
end

--- Stops all audio managed by this instance
function Audio:stopAll()
end

--- Returns the object associated with the id returned by a call to `play`.
--- What this object is depends on the specific audio implementation.
---@param id integer
---@return unknown
function Audio:readId(id)
    return nil
end

return sounding