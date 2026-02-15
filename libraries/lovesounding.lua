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
---@field pitch? number The pitch of the sound (will be combined with any other pitch settings)
---@field semitoneShift? number Like pitch, but in semitones rather than a multiplicative pitch value
---@field volume? number Volume of the sound
---@field positionX? number The X position of the sound in space
---@field positionY? number The Y position of the sound in space
---@field positionZ? number The Z position of the sound in space
---@field velocityX? number The X velocity of the sound in space
---@field velocityY? number The Y velocity of the sound in space
---@field velocityZ? number The Z velocity of the sound in space
---@field filterEnabled? boolean Whether or not filtering is enabled. Must be set to `true` for `filterSettings` to do anything.
---@field filterSettings? {type: love.FilterType, volume: number, highgain: number, lowgain: number} Configures the filter for the sound

--- A basic sound effect
---@class Sounding.Sound : Sounding.Audio
---@field baseSource love.Source
---@field sources love.Source[]
---@field nextFreeSource integer
---@field maxSources integer
---@field sourcePriorityMode Sounding.SourcePriorityMode
---@field allowSpatialOptions boolean
---@field basePitch number
---@field baseVolume number
---@field randomPitchScale number
local Sound = {}
local SoundMT = {__index = Sound}

--- Options for what should happen when the source in a `Sounding.Sound` is still playing when another sound tries to play
---@alias Sounding.SourcePriorityMode
---| '"stop_old"' # When a source is busy and new sound wants to play, the old one is stopped to make room for the next
---| '"cancel_new"' # When a source is busy and a new sound wants to play, the new sound is cancelled and doesn't play

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

--- Creates a new SFX. Should usually be made from a static source.
---@param source love.Source
---@return Sounding.Sound
function sounding.newSound(source)
    ---@type Sounding.Sound
    local sound = {
        baseSource = source,
        sources = {},
        nextFreeSource = 1,
        maxSources = 5,
        sourcePriorityMode = "stop_old",
        allowSpatialOptions = true,
        basePitch = 1,
        baseVolume = 1,
        randomPitchScale = 1,
    }

    -- I can't find a better way to automatically check if the source is mono and allows directional stuff lol
    if not pcall(source.getPosition, source) then sound.allowSpatialOptions = false end

    return setmetatable(sound, SoundMT)
end

--- Plays the sound and returns the id of the source or nil if no sound was played.
---@param options? Sounding.AudioOptions
---@return integer? sourceIndex
function Sound:play(options)
    local sources = self.sources

    local nextFreeSource = self.nextFreeSource
    local maxSources = self.maxSources

    if nextFreeSource > maxSources then nextFreeSource = 1 end
    if not sources[nextFreeSource] then
        sources[nextFreeSource] = self.baseSource:clone()
    end

    local source = sources[nextFreeSource]

    if source:isPlaying() then
        if self.sourcePriorityMode == "cancel_new" then return nil end
        source:stop()
    end

    self:applySourceOptions(source, options)
    if not source:play() then return nil end

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

--- Changes the options for all sources that are currently playing
---@param options Sounding.AudioOptions
function Sound:setDynamicOptions(options)
    local sources = self.sources
    for sourceIndex = 1, self.maxSources do
        local source = sources[sourceIndex]
        if source and source:isPlaying() then self:applySourceOptions(source, options, true) end
    end
end

---@param id integer
---@return love.Source
function Sound:readId(id)
    return self.sources[id]
end

---@return string
function Sound:type()
    return "Sound"
end

----------

--- Sets how many clones of the base source can be created for this sfx at most
---@param maxSources integer
function Sound:setMaxSources(maxSources)
    if maxSources < 1 then error("Invalid max source count", 2) end

    for sourceIndex = maxSources + 1, self.maxSources, 1 do
        self.sources[sourceIndex] = nil
    end

    self.maxSources = maxSources
end

--- Sets what should happen when this sound tries to play
--- but the source it's trying to use is busy.
---@param sourcePriorityMode Sounding.SourcePriorityMode
function Sound:setSourcePriorityMode(sourcePriorityMode)
    self.sourcePriorityMode = sourcePriorityMode
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

---@param volume number
---@return self
function Sound:setBaseVolume(volume)
    if volume < 0 or volume > 1 then error("Invalid volume", 2) end
    self.baseVolume = volume
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

-- https://github.com/mixxxdj/mixxx/wiki/pitch_percentages_for_semitones_and_notes
local semitoneMultiplicativeIncrease = 1.0595
---@param semitoneShift number
local function semitoneShiftToPitch(semitoneShift)
    if semitoneShift == 0 then return 1 end

    local pitch = 1

    local mult = (semitoneShift >= 0) and (semitoneMultiplicativeIncrease) or (1 / semitoneMultiplicativeIncrease)
    semitoneShift = math.abs(semitoneShift)

    -- A lookup table of pitches could ease this for loop but there's probably no point
    for i = 1, semitoneShift do
        pitch = pitch * mult
    end

    local semitoneShiftFine = semitoneShift % 1
    local pitchNext = pitch * mult
    pitch = pitch + (pitchNext - pitch) * semitoneShiftFine

    return pitch
end

---@private
---@param source love.Source
---@param options Sounding.AudioOptions?
---@param optionsAreDynamic? boolean
function Sound:applySourceOptions(source, options, optionsAreDynamic)
    self:applySourcePitch(source, options, optionsAreDynamic)
    self:applySourceVolume(source, options, optionsAreDynamic)
    self:applySourcePosition(source, options,optionsAreDynamic)
    self:applySourceVelocity(source, options, optionsAreDynamic)
    self:applySourceFilter(source, options, optionsAreDynamic)
end

---@private
---@param source love.Source
---@param options Sounding.AudioOptions?
---@param optionsAreDynamic? boolean
function Sound:applySourcePitch(source, options, optionsAreDynamic)
    local pitch = self.basePitch
    local randomPitchScale = self.randomPitchScale

    if optionsAreDynamic then
        randomPitchScale = 1
        if options and not (options.pitch or options.semitoneShift) then return end -- If we're not touching pitch, don't screw up the randomness of it
    end

    if options then
        pitch = pitch * (options.pitch or 1)
        pitch = pitch * semitoneShiftToPitch(options.semitoneShift or 0)
    end

    local pitchMin = pitch / randomPitchScale
    local pitchMax = pitch * randomPitchScale

    pitch = pitchMin + sounding.randomFn() * (pitchMax - pitchMin)
    source:setPitch(pitch)
end

---@private
---@param source love.Source
---@param options Sounding.AudioOptions?
---@param optionsAreDynamic? boolean
function Sound:applySourceVolume(source, options, optionsAreDynamic)
    if optionsAreDynamic and options and not options.volume then return end

    local volume = self.baseVolume
    volume = volume * (options and options.volume or 1)
    source:setVolume(volume)
end

---@private
---@param source love.Source
---@param options Sounding.AudioOptions?
---@param optionsAreDynamic? boolean
function Sound:applySourcePosition(source, options, optionsAreDynamic)
    if not self.allowSpatialOptions then return end

    local xDefault = 0
    local yDefault = 0
    local zDefault = 0
    if optionsAreDynamic then xDefault, yDefault, zDefault = source:getPosition() end

    local x = options and options.positionX or xDefault
    local y = options and options.positionY or yDefault
    local z = options and options.positionZ or zDefault

    source:setPosition(x, y, z)
end

---@private
---@param source love.Source
---@param options Sounding.AudioOptions?
---@param optionsAreDynamic? boolean
function Sound:applySourceVelocity(source, options, optionsAreDynamic)
    if not self.allowSpatialOptions then return end

    local xDefault = 0
    local yDefault = 0
    local zDefault = 0
    if optionsAreDynamic then xDefault, yDefault, zDefault = source:getVelocity() end

    local x = options and options.velocityX or xDefault
    local y = options and options.velocityY or yDefault
    local z = options and options.velocityZ or zDefault

    source:setVelocity(x, y, z)
end

---@private
---@param source love.Source
---@param options Sounding.AudioOptions?
---@param optionsAreDynamic? boolean
function Sound:applySourceFilter(source, options, optionsAreDynamic)
    if optionsAreDynamic and options and options.filterEnabled == nil then return end

    if not options then return end
    if not options.filterEnabled or not options.filterSettings then
        source:setFilter()
    else
        source:setFilter(options.filterSettings)
    end
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

--- Changes the options for all sounds that are currently playing
---@param options Sounding.AudioOptions
function RandomizedSound:setDynamicOptions(options)
    local sounds = self.sounds
    for soundIndex = 1, #sounds do
        sounds[soundIndex]:setDynamicOptions(options)
    end
end

---@param id integer
---@return Sounding.Audio
function RandomizedSound:readId(id)
    return self.sounds[id]
end

---@return string
function RandomizedSound:type()
    return "RandomizedSound"
end

----------

---@param sound Sounding.Audio
function RandomizedSound:addSoundOption(sound)
    self.sounds[#self.sounds+1] = sound
end

-- The abstract shared Audio interface -------------------------------------------------------------

--- Plays the audio and returns some sort of identifier for it (if applicable)
---@param options? Sounding.AudioOptions
---@return integer id?
function Audio:play(options)
    return 0
end

--- Stops all audio managed by this instance
function Audio:stopAll()
end

--- Changes the options for any audio that's already playing (does not affect audio played from the next call to `play()`)
---@param options Sounding.AudioOptions
function Audio:setDynamicOptions(options)
end

--- Returns the object associated with the id returned by a call to `play`.
--- What this object is depends on the specific audio implementation.
---@param id integer
---@return unknown
function Audio:readId(id)
    return nil
end

--- Returns the class name
---@return string
function Audio:type()
    return "Audio"
end

return sounding