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

--- The shared interface for all types of sounds and music,
--- documented at the bottom of the file.
---@class Sounding.Audio
---@field customData table<string, any> Any arbitrary data associated with the audio
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
---@field effectEnabled? boolean Toggles whether the effect given by `effectName` will be enabled or disabled. Not setting this will make that setting be ignored.
---@field effectName? string The name of the effect to be enabled or disabled
---@field effectFilterSettings? {type: love.FilterType, volume: number, highgain: number, lowgain: number} Configures the filter of the audio that's passed into the effect being enabled.

--- ^ it's currently impossible to play a single source with multiple effects applied (without using dynamic options, but those affect all sources).
--- Could be fixed by having another field which is an array of more effect options, but it seems overkill.
--- If you want many filters applied at the same time, chances are it's better to just get a clone of the audio
--- and then going ham with setting the dynamic options.
--- But I dunno. Maybe I'll add it at some point later(tm).

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

--- A sound that plays all of its audios at once
---@class Sounding.LayeredSound : Sounding.Audio
---@field sounds Sounding.Audio[]
local LayeredSound = {}
local LayeredSoundMT = {__index = LayeredSound}

--- A sound that can modify the set audio option assigned to it when asked to be played
---@class Sounding.OptionRemappingSound : Sounding.Audio
---@field sound Sounding.Audio The sound that actually handles the playing of the newly modified options
---@field optionName string
---@field optionBaseValue unknown
---@field optionReferenceValue unknown
---@field remappingFn fun(optionName: string, optionCurrentValue: unknown, optionReferenceValue: unknown, customData: table<string, any>): unknown The function that returns the remapped option
local OptionRemappingSound = {}
local OptionRemappingSoundMT = {__index = OptionRemappingSound}

--- A sound that tries to play the closest matching defined audio to the configured numeric-value audio option
---@class Sounding.OptionTargetedSound : Sounding.Audio
---@field sounds ([Sounding.Audio, number])[] The sounds and their assigned value, sorted
---@field optionName string
---@field optionBaseValue number
local OptionTargetedSound = {}
local OptionTargetedSoundMT = {__index = OptionTargetedSound}

-- Main interface ----------------------------------------------------------------------------------

--- Plays a registered audio
---@param soundId string
---@param options? Sounding.AudioOptions
function sounding.play(soundId, options)
    local sound = sounding.registeredSounds[soundId]
    if not sound then error(string.format("There is no registered sound with the ID '%s'", soundId), 2) end
    sound:play(options)
end

--- Like `play()`, but doesn't error if an audio under the given soundId is not registered (and just does nothing instead)
---@param soundId string
---@param options? Sounding.AudioOptions
function sounding.tryPlay(soundId, options)
    if not sounding.registeredSounds[soundId] then return end
    return sounding.play(soundId, options)
end

--- Returns a registered audio object
---@param soundId string
---@return Sounding.Audio
function sounding.get(soundId)
    return sounding.registeredSounds[soundId]
end

--- Returns the table of all registered audio
---@return table<string, Sounding.Audio>
function sounding.getAll()
    return sounding.registeredSounds
end

--- Registers an audio to the main global interface
---@param soundId string
---@param audio Sounding.Audio
function sounding.register(soundId, audio)
    if sounding.registeredSounds[soundId] then error(string.format("There is already a registered sound with the ID '%s'", soundId), 2) end
    sounding.registeredSounds[soundId] = audio
end

--- An optional callback function can be put here
--- to be called each time any audio is played.
--- 
--- The `audio` parameter is the audio `play()` was actually called on,
--- `actualPlayedAudio` is the audio which actually produced the sound.
--- These may be the same.
--- 
--- For some audios, this callback may be triggered multiple times.
---@type fun(audio: Sounding.Audio, actualPlayedAudio: Sounding.Audio)?
sounding.audioPlayedCallback = nil

--- An optional function can be put here
--- which will be called every time any audio is played
--- and the returned value will be used to multiply its volume.
--- 
--- Parameters are the same as in `audioPlayedCallback`.
---@type (fun(audio: Sounding.Audio, actualPlayedAudio: Sounding.Audio): number)?
sounding.getGlobalVolumeMultiplier = nil

---@type table<string, Sounding.Audio>
sounding.registeredSounds = {}

-- Sounds ------------------------------------------------------------------------------------------

--- Creates a new SFX. Should usually be made from a static source.
---@param source love.Source
---@return Sounding.Sound
function sounding.newSound(source)
    ---@type Sounding.Sound
    local sound = {
        customData = {},
        baseSource = source,
        sources = {},
        nextFreeSource = 1,
        maxSources = 3,
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

--- Like `sounding.newSound()`, but optimises the Sound object for playing a single (likely streamed) source of music
--- rather than having many clones of a sound effect.
---@param source love.Source
---@return Sounding.Sound
function sounding.newSong(source)
    local sound = sounding.newSound(source)
    sound:setMaxSources(1)
    return sound
end

--- Plays the sound and returns the id of the source or nil if no sound was played.
---@param options? Sounding.AudioOptions
---@param rootAudio? Sounding.Audio
---@return integer? sourceIndex
function Sound:play(options, rootAudio)
    rootAudio = rootAudio or self
    local sources = self.sources

    local nextFreeSource = self.nextFreeSource
    local maxSources = self.maxSources

    if nextFreeSource > maxSources then nextFreeSource = 1 end
    if not sources[nextFreeSource] then
        sources[nextFreeSource] = (nextFreeSource == 1 and self.baseSource) or (self.baseSource:clone())
    end

    local source = sources[nextFreeSource]

    if source:isPlaying() then
        if self.sourcePriorityMode == "cancel_new" then return nil end
        source:stop()
    end

    self:applySourceOptions(source, rootAudio, options)
    if not source:play() then return nil end

    if sounding.audioPlayedCallback then sounding.audioPlayedCallback(rootAudio, self) end

    self.nextFreeSource = nextFreeSource + 1
    return nextFreeSource
end

function Sound:stop()
    local sources = self.sources
    for sourceIndex = 1, self.maxSources do
        local source = sources[sourceIndex]
        if source then source:stop() end
    end
end

---@return boolean
function Sound:isPlaying()
    local sources = self.sources
    for sourceIndex = 1, self.maxSources do
        local source = sources[sourceIndex]
        if source and source:isPlaying() then return true end
    end
    return false
end

---@param loop boolean
function Sound:setLooping(loop)
    local sources = self.sources
    for sourceIndex = 1, self.maxSources do
        local source = sources[sourceIndex]
        if source then source:setLooping(loop) end
    end
end

--- Changes the options for all sources that are currently playing
---@param options Sounding.AudioOptions
---@param rootAudio? Sounding.Audio
function Sound:setDynamicOptions(options, rootAudio)
    rootAudio = rootAudio or self
    local sources = self.sources
    for sourceIndex = 1, self.maxSources do
        local source = sources[sourceIndex]
        if source and source:isPlaying() then self:applySourceOptions(source, rootAudio, options, true) end
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

---@param key string
---@param value any
function Sound:setCustomDataField(key, value)
    self.customData[key] = value
end

---@param key string
---@return any
function Sound:getCustomDataField(key)
    return self.customData[key]
end

---@return Sounding.Sound
function Sound:clone()
    ---@type Sounding.Sound
    local clone = {
        customData = {},
        baseSource = self.baseSource:clone(),
        sources = {},
        nextFreeSource = 1,
        maxSources = self.maxSources,
        sourcePriorityMode = self.sourcePriorityMode,
        allowSpatialOptions = self.allowSpatialOptions,
        basePitch = self.basePitch,
        baseVolume = self.baseVolume,
        randomPitchScale = self.randomPitchScale,
    }

    for key in pairs(self.customData) do
        clone.customData[key] = self.customData[key]
    end

    return setmetatable(clone, SoundMT)
end

---@return Sounding.Sound
function Sound:cloneTiny()
    local clone = self:clone()
    clone.maxSources = 1
    return clone
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

--- Turns a relative shift of semitones to a multiplicative pitch value
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
sounding.semitoneShiftToPitch = semitoneShiftToPitch

-- These following applySourceWhatever methods are a bit of a mess,
-- but the idea is that if the options are dynamic,
-- nothing that's already running should be touched unless explicitly changed by the options table,
-- and if the options aren't dynamic,
-- the source should be first reset into its default starting state and turn off any special effects.
--
-- Maybe it would have been better to have these separated into reset and apply effect methods,
-- but that would make some shenanigans with the pitch logic a bit messy to do anyways
-- (dynamically changing the pitch just sets it, but setting the pitch just once when playing the audio combines that with the random pitch scale).

---@private
---@param source love.Source
---@param rootAudio Sounding.Audio
---@param options Sounding.AudioOptions?
---@param optionsAreDynamic? boolean
function Sound:applySourceOptions(source, rootAudio, options, optionsAreDynamic)
    self:applySourcePitch(source, rootAudio, options, optionsAreDynamic)
    self:applySourceVolume(source, rootAudio, options, optionsAreDynamic)
    self:applySourcePosition(source, rootAudio, options,optionsAreDynamic)
    self:applySourceVelocity(source, rootAudio, options, optionsAreDynamic)
    self:applySourceFilter(source, rootAudio, options, optionsAreDynamic)
    self:applySourceEffect(source, rootAudio, options, optionsAreDynamic)
end

---@private
---@param source love.Source
---@param rootAudio Sounding.Audio
---@param options Sounding.AudioOptions?
---@param optionsAreDynamic? boolean
function Sound:applySourcePitch(source, rootAudio, options, optionsAreDynamic)
    local pitch = self.basePitch
    local randomPitchScale = self.randomPitchScale

    if optionsAreDynamic then
        randomPitchScale = 1
        if not options or not (options.pitch or options.semitoneShift) then return end -- If we're not touching pitch, don't screw up the randomness of it
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
---@param rootAudio Sounding.Audio
---@param options Sounding.AudioOptions?
---@param optionsAreDynamic? boolean
function Sound:applySourceVolume(source, rootAudio, options, optionsAreDynamic)
    if optionsAreDynamic and (not options or not options.volume) then return end

    local volume = self.baseVolume
    volume = volume * (sounding.getGlobalVolumeMultiplier and sounding.getGlobalVolumeMultiplier(rootAudio, self) or 1)
    volume = volume * (options and options.volume or 1)
    source:setVolume(volume)
end

---@private
---@param source love.Source
---@param rootAudio Sounding.Audio
---@param options Sounding.AudioOptions?
---@param optionsAreDynamic? boolean
function Sound:applySourcePosition(source, rootAudio, options, optionsAreDynamic)
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
---@param rootAudio Sounding.Audio
---@param options Sounding.AudioOptions?
---@param optionsAreDynamic? boolean
function Sound:applySourceVelocity(source, rootAudio, options, optionsAreDynamic)
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
---@param rootAudio Sounding.Audio
---@param options Sounding.AudioOptions?
---@param optionsAreDynamic? boolean
function Sound:applySourceFilter(source, rootAudio, options, optionsAreDynamic)
    if optionsAreDynamic then
        if not options then return end
        if options.filterEnabled == nil then return end
        if options.filterEnabled and not options.filterSettings then return end
    end

    if not options or not options.filterEnabled or not options.filterSettings then
        source:setFilter()
    else
        source:setFilter(options.filterSettings)
    end
end

---@private
---@param source love.Source
---@param rootAudio Sounding.Audio
---@param options Sounding.AudioOptions?
---@param optionsAreDynamic? boolean
function Sound:applySourceEffect(source, rootAudio, options, optionsAreDynamic)
    if not optionsAreDynamic then
        local effects = source:getActiveEffects()
        for effectIndex = 1, #effects do
            source:setEffect(effects[effectIndex], false)
        end
    end

    if not options then return end
    if not options.effectName then return end
    if options.effectEnabled == nil then return end

    if not options.effectEnabled then
        source:setEffect(options.effectName, false)
        return
    end

    if options.effectFilterSettings then
        source:setEffect(options.effectName, options.effectFilterSettings)
        return
    end

    source:setEffect(options.effectName, true)
end

--------------------------------------------------

--- Creates a new sound for playing randomly from a set of different `Sounding.Audio`s.
---@param ... Sounding.Audio
---@return Sounding.RandomizedSound
function sounding.newRandomizedSound(...)
    ---@type Sounding.RandomizedSound
    local sound = {
        customData = {},
        sounds = {...}
    }
    return setmetatable(sound, RandomizedSoundMT)
end

---@param options? Sounding.AudioOptions
---@param rootAudio? Sounding.Audio
---@return integer? soundIndex
function RandomizedSound:play(options, rootAudio)
    local sounds = self.sounds
    if #sounds == nil then return nil end
    local soundIndex = sounding.randomFn(#sounds)

    sounds[soundIndex]:play(options, rootAudio or self)
    return soundIndex
end

function RandomizedSound:stop()
    local sounds = self.sounds
    for soundIndex = 1, #sounds do
        sounds[soundIndex]:stop()
    end
end

---@return boolean
function RandomizedSound:isPlaying()
    local sounds = self.sounds
    for soundIndex = 1, #sounds do
        if sounds[soundIndex]:isPlaying() then return true end
    end
    return false
end

---@param loop boolean
function RandomizedSound:setLooping(loop)
    local sounds = self.sounds
    for soundIndex = 1, #sounds do
        sounds[soundIndex]:setLooping(loop)
    end
end

--- Changes the options for all sounds that are currently playing
---@param options Sounding.AudioOptions
---@param rootAudio? Sounding.Audio
function RandomizedSound:setDynamicOptions(options, rootAudio)
    local sounds = self.sounds
    for soundIndex = 1, #sounds do
        sounds[soundIndex]:setDynamicOptions(options, rootAudio or self)
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

---@param key string
---@param value any
function RandomizedSound:setCustomDataField(key, value)
    self.customData[key] = value
end

---@param key string
---@return any
function RandomizedSound:getCustomDataField(key)
    return self.customData[key]
end

---@return Sounding.RandomizedSound
function RandomizedSound:clone()
    local clone = sounding.newRandomizedSound()

    local soundsSelf = self.sounds
    local soundsClone = clone.sounds
    for soundIndex = 1, #soundsSelf do
        soundsClone[soundIndex] = soundsSelf[soundIndex]:clone()
    end

    for key in pairs(self.customData) do
        clone.customData[key] = self.customData[key]
    end

    return clone
end

---@return Sounding.RandomizedSound
function RandomizedSound:cloneTiny()
    local clone = sounding.newRandomizedSound()

    local soundsSelf = self.sounds
    local soundsClone = clone.sounds
    for soundIndex = 1, #soundsSelf do
        soundsClone[soundIndex] = soundsSelf[soundIndex]:cloneTiny()
    end

    for key in pairs(self.customData) do
        clone.customData[key] = self.customData[key]
    end

    return clone
end

----------

--- Adds a new option for the randomized sound to manage.
--- 
--- The randomized sound will own and manage this sound completely,
--- so make sure to clone it first if you plan on using it elsewhere too.
---@param sound Sounding.Audio
function RandomizedSound:addSoundOption(sound)
    self.sounds[#self.sounds+1] = sound
end

--------------------------------------------------

--- Creates a new sound for playing all of many different `Sounding.Audio`s at once.
--- Playing this also triggers the audio played callback many times, once for each played held audio object.
---@param ... Sounding.Audio
---@return Sounding.LayeredSound
function sounding.newLayeredSound(...)
    ---@type Sounding.LayeredSound
    local sound = {
        customData = {},
        sounds = {...}
    }
    return setmetatable(sound, LayeredSoundMT)
end

---@param options? Sounding.AudioOptions
---@param rootAudio? Sounding.Audio
---@return integer? soundIndex
function LayeredSound:play(options, rootAudio)
    local sounds = self.sounds
    for soundIndex = 1, #sounds do
        sounds[soundIndex]:play(options, rootAudio or self)
    end
    return 1
end

function LayeredSound:stop()
    local sounds = self.sounds
    for soundIndex = 1, #sounds do
        sounds[soundIndex]:stop()
    end
end

---@return boolean
function LayeredSound:isPlaying()
    local sounds = self.sounds
    for soundIndex = 1, #sounds do
        if sounds[soundIndex]:isPlaying() then return true end
    end
    return false
end

---@param loop boolean
function LayeredSound:setLooping(loop)
    local sounds = self.sounds
    for soundIndex = 1, #sounds do
        sounds[soundIndex]:setLooping(loop)
    end
end

---@param options Sounding.AudioOptions
---@param rootAudio? Sounding.Audio
function LayeredSound:setDynamicOptions(options, rootAudio)
    local sounds = self.sounds
    for soundIndex = 1, #sounds do
        sounds[soundIndex]:setDynamicOptions(options, rootAudio or self)
    end
end

---@param id integer
---@return Sounding.Audio
function LayeredSound:readId(id)
    return self.sounds[id]
end

---@return string
function LayeredSound:type()
    return "LayeredSound"
end

---@param key string
---@param value any
function LayeredSound:setCustomDataField(key, value)
    self.customData[key] = value
end

---@param key string
---@return any
function LayeredSound:getCustomDataField(key)
    return self.customData[key]
end

---@return Sounding.LayeredSound
function LayeredSound:clone()
    local clone = sounding.newLayeredSound()

    local soundsSelf = self.sounds
    local soundsClone = clone.sounds
    for soundIndex = 1, #soundsSelf do
        soundsClone[soundIndex] = soundsSelf[soundIndex]:clone()
    end

    for key in pairs(self.customData) do
        clone.customData[key] = self.customData[key]
    end

    return clone
end

---@return Sounding.LayeredSound
function LayeredSound:cloneTiny()
    local clone = sounding.newLayeredSound()

    local soundsSelf = self.sounds
    local soundsClone = clone.sounds
    for soundIndex = 1, #soundsSelf do
        soundsClone[soundIndex] = soundsSelf[soundIndex]:cloneTiny()
    end

    for key in pairs(self.customData) do
        clone.customData[key] = self.customData[key]
    end

    return clone
end

----------

--- Adds a new option for the sound to layer.
--- 
--- The layered sound will own and manage this sound completely,
--- so make sure to clone it first if you plan on using it elsewhere too.
---@param sound Sounding.Audio
function LayeredSound:addSoundOption(sound)
    self.sounds[#self.sounds+1] = sound
end

--------------------------------------------------

local function defaultRemappingFn(optionName, optionCurrentValue, optionReferenceValue, customData)
    if type(optionCurrentValue) == "number" and type(optionReferenceValue) == "number" then return optionCurrentValue - optionReferenceValue end
    return optionReferenceValue
end

--- Creates a sound that can remap one given sound option each time it's played.
--- 
--- For example, it can make the sound always play at double the otherwise expected volume.
--- 
--- If the remapping function isn't configured,
--- the default one tries to set the option to be linearly relative to the configured reference value
--- (e.g. if the base value is 1 and the audio is trying to play at value 3, it actually plays with the value set to 2).
--- If the base value isn't numeric, it is simply set to the base value instead.
---@param playbackSound Sounding.Audio The sound that will take care of the actual playback once the option has been re-mapped (as with other wrapped sounds, this audio is fully owned by the remapping sound)
---@return Sounding.OptionRemappingSound
function sounding.newOptionRemappingSound(playbackSound)
    ---@type Sounding.OptionRemappingSound
    local sound = {
        customData = {},
        sound = playbackSound,
        optionName = "volume",
        optionBaseValue = 1,
        optionReferenceValue = 1,
        remappingFn = defaultRemappingFn
    }
    return setmetatable(sound, OptionRemappingSoundMT)
end

---@param options? Sounding.AudioOptions
---@param rootAudio? Sounding.Audio
---@return integer 1
function OptionRemappingSound:play(options, rootAudio)
    local optionName = self.optionName

    options = options or {}
    local originalValue = options[optionName]
    local fedValue = originalValue == nil and self.optionBaseValue or originalValue

    options[optionName] = self.remappingFn(optionName, fedValue, self.optionReferenceValue, self.customData)
    self.sound:play(options, rootAudio or self)

    options[optionName] = originalValue
    return 1
end

function OptionRemappingSound:stop()
    self.sound:stop()
end

---@return boolean
function OptionRemappingSound:isPlaying()
    return self.sound:isPlaying()
end

---@param loop boolean
function OptionRemappingSound:setLooping(loop)
    self.sound:setLooping(loop)
end

---@param options Sounding.AudioOptions
---@param rootAudio? Sounding.Audio
function OptionRemappingSound:setDynamicOptions(options, rootAudio)
    self.sound:setDynamicOptions(options, rootAudio or self)
end

---@param id integer
---@return Sounding.Audio
function OptionRemappingSound:readId(id)
    return self.sound
end

---@return string
function OptionRemappingSound:type()
    return "OptionRemappingSound"
end

---@param key string
---@param value any
function OptionRemappingSound:setCustomDataField(key, value)
    self.customData[key] = value
end

---@param key string
---@return any
function OptionRemappingSound:getCustomDataField(key)
    return self.customData[key]
end

---@return Sounding.OptionRemappingSound
function OptionRemappingSound:clone()
    local clone = sounding.newOptionRemappingSound(self.sound:clone())
    clone.optionName = self.optionName
    clone.optionBaseValue = self.optionBaseValue
    clone.optionReferenceValue = self.optionReferenceValue
    clone.remappingFn = self.remappingFn

    for key in pairs(self.customData) do
        clone.customData[key] = self.customData[key]
    end

    return clone
end

---@return Sounding.OptionRemappingSound
function OptionRemappingSound:cloneTiny()
    local clone = sounding.newOptionRemappingSound(self.sound:cloneTiny())
    clone.optionName = self.optionName
    clone.optionBaseValue = self.optionBaseValue
    clone.optionReferenceValue = self.optionReferenceValue
    clone.remappingFn = self.remappingFn

    for key in pairs(self.customData) do
        clone.customData[key] = self.customData[key]
    end

    return clone
end

----------

--- Configures the option that gets targeted.
--- 
--- The `baseValue` is the value that the option is considered to have if it hasn't been set (this is useful to set as the neutral value, e.g. `1` for audio). Can be nil.
--- The `referenceValue` is the value that gets passed to the remapping function in case it needs a configured reference to use for whatever reason. Can be nil.
--- 
--- The remapping function should probably be configured alongside this.
---@param name string
---@param baseValue unknown
---@param referenceValue unknown
function OptionRemappingSound:configureOption(name, baseValue, referenceValue)
    self.optionName = name
    self.optionBaseValue = baseValue
    self.optionReferenceValue = referenceValue
end

--- Configures the function that re-maps the configured option. It should return the new value for the option.
---@param remappingFn fun(optionName: string, optionCurrentValue: unknown, optionReferenceValue: unknown, customData: table<string, any>): unknown
function OptionRemappingSound:configureRemappingFn(remappingFn)
    self.remappingFn = remappingFn
end

--------------------------------------------------

--- Creates a sound that always tries to play the closest matching sound to the configured numeric-value audio option.
--- 
--- When adding an audio to this sound, you define its value for that audio option. Maybe the configured option is volume, and you say the added sound has volume 0.5, for example.
--- Then, when a sound is requested to play with the volume audio option set,
--- all the audios in this sound are searched to play the closest matching one (so if the volume is set to 0.5, the earlier mentioned added sound will play, and if it's 0.6, it will probably play too, unless there's an audio with volume even closer to 0.6 added).
--- 
--- Note that the audio option is kept unchanged. So if the target sound truly does play at half volume relative to all other sounds by itself,
--- it will actually now be only at 25% volume of other sounds, as it's being played at volume 0.5.
--- If it should instead act relatively, and be played at volume 1 if the target volume matched exactly,
--- it should be wrapped in an OptionRemappingSound object.
---@return Sounding.OptionTargetedSound
function sounding.newOptionTargetedSound()
    ---@type Sounding.OptionTargetedSound
    local sound = {
        customData = {},
        sounds = {},
        optionName = "volume",
        optionBaseValue = 1
    }
    return setmetatable(sound, OptionTargetedSoundMT)
end

---@param options? Sounding.AudioOptions
---@param rootAudio? Sounding.Audio
---@return integer? soundIndex
function OptionTargetedSound:play(options, rootAudio)
    local targetValue = options and options[self.optionName] or self.optionBaseValue
    local sound, soundIndex = self:findClosestSound(targetValue)
    if not sound then return nil end

    sound:play(options, rootAudio or self)
    return soundIndex
end

function OptionTargetedSound:stop()
    local sounds = self.sounds
    for soundIndex = 1, #sounds do
        sounds[soundIndex][1]:stop()
    end
end

---@return boolean
function OptionTargetedSound:isPlaying()
    local sounds = self.sounds
    for soundIndex = 1, #sounds do
        if sounds[soundIndex][1]:isPlaying() then return true end
    end
    return false
end

---@param loop boolean
function OptionTargetedSound:setLooping(loop)
    local sounds = self.sounds
    for soundIndex = 1, #sounds do
        sounds[soundIndex][1]:setLooping(loop)
    end
end

--- Changes the options for all sounds that are currently playing
---@param options Sounding.AudioOptions
---@param rootAudio? Sounding.Audio
function OptionTargetedSound:setDynamicOptions(options, rootAudio)
    local sounds = self.sounds
    for soundIndex = 1, #sounds do
        sounds[soundIndex][1]:setDynamicOptions(options, rootAudio or self)
    end
end

---@param id integer
---@return Sounding.Audio
function OptionTargetedSound:readId(id)
    return self.sounds[id][1]
end

---@return string
function OptionTargetedSound:type()
    return "OptionTargetedSound"
end

---@param key string
---@param value any
function OptionTargetedSound:setCustomDataField(key, value)
    self.customData[key] = value
end

---@param key string
---@return any
function OptionTargetedSound:getCustomDataField(key)
    return self.customData[key]
end

---@return Sounding.OptionTargetedSound
function OptionTargetedSound:clone()
    local clone = sounding.newOptionTargetedSound()

    clone.optionName = self.optionName
    clone.optionBaseValue = self.optionBaseValue

    local soundsSelf = self.sounds
    local soundsClone = clone.sounds
    for soundIndex = 1, #soundsSelf do
        local sound = soundsSelf[soundIndex]
        soundsClone[soundIndex] = {sound[1]:clone(), sound[2]}
    end

    for key in pairs(self.customData) do
        clone.customData[key] = self.customData[key]
    end

    return clone
end

---@return Sounding.OptionTargetedSound
function OptionTargetedSound:cloneTiny()
    local clone = sounding.newOptionTargetedSound()

    clone.optionName = self.optionName
    clone.optionBaseValue = self.optionBaseValue

    local soundsSelf = self.sounds
    local soundsClone = clone.sounds
    for soundIndex = 1, #soundsSelf do
        local sound = soundsSelf[soundIndex]
        soundsClone[soundIndex] = {sound[1]:cloneTiny(), sound[2]}
    end

    for key in pairs(self.customData) do
        clone.customData[key] = self.customData[key]
    end

    return clone
end

----------

--- Configures the option that gets targeted.
--- The `baseValue` is the value that gets searched for in the added sounds
--- if the configured option isn't explicitly set when attempting to play the sound
--- (this should be the neutral value, e.g. `1` for audio)
---@param name string
---@param baseValue number
function OptionTargetedSound:configureOption(name, baseValue)
    self.optionName = name
    self.optionBaseValue = baseValue
end

--- Registers the given sound alongside its given value.
--- 
--- The option-targeted sound will own and manage this sound completely,
--- so make sure to clone it first if you plan on using it elsewhere too.
---@param value number
---@param sound Sounding.Audio
function OptionTargetedSound:addSound(value, sound)
    local _, closestSoundIndex = self:findClosestSound(value)
    if not closestSoundIndex then
        self.sounds[1] = {sound, value}
        return
    end

    local closestSoundPair = self.sounds[closestSoundIndex]

    if closestSoundPair[2] <= value then
        table.insert(self.sounds, closestSoundIndex + 1, {sound, value})
    else
        table.insert(self.sounds, closestSoundIndex, {sound, value})
    end
end

--- Returns the sound that closest matches the target value.
--- Returns nil if there are no sounds added.
---@param targetValue number
---@return Sounding.Audio? sound
---@return integer? soundIndex
function OptionTargetedSound:findClosestSound(targetValue)
    local sounds = self.sounds
    if #sounds == 0 then return nil, nil end

    local indexFirst = 1
    local indexLast = #sounds
    while indexFirst < indexLast do
        local index = math.floor((indexFirst + indexLast) / 2)
        local sound = sounds[index]
        local audio = sound[1]
        local value = sound[2]

        if value == targetValue then
            return audio, index
        end

        if value < targetValue then
            indexFirst = index + 1
        else
            indexLast = index
        end
    end

    local closeEnoughIndexA = indexFirst
    local closeEnoughIndexB = indexFirst - 1
    if closeEnoughIndexB < 1 then return sounds[closeEnoughIndexA][1], closeEnoughIndexA end

    local closeEnoughValueA = sounds[closeEnoughIndexA][2]
    local closeEnoughValueB = sounds[closeEnoughIndexB][2]
    local distanceA = math.abs(closeEnoughValueA - targetValue)
    local distanceB = math.abs(closeEnoughValueB - targetValue)

    if distanceA < distanceB then return sounds[closeEnoughIndexA][1], closeEnoughIndexA end
    return sounds[closeEnoughIndexB][1], closeEnoughIndexB
end

-- The abstract shared Audio interface -------------------------------------------------------------

--- Plays the audio and returns some sort of identifier for it (if applicable).
--- 
--- The `rootAudio` parameter is used (internally) to trigger callbacks on the correct topmost audio object that got triggered.
--- You most likely don't need to worry about it.
---@param options? Sounding.AudioOptions
---@param rootAudio? Sounding.Audio
---@return integer? id
function Audio:play(options, rootAudio)
    return nil
end

--- Stops all audio managed by this instance
function Audio:stop()
end

--- Returns true if any audio managed by this instance is currently playing
---@return boolean
function Audio:isPlaying()
    return false
end

--- Sets whether or not the sounds played by this instance should loop.
--- 
--- This is generally a bad idea for any Audio that's managed globally,
--- but can be good for audio that a specific object owns
--- (e.g. a car engine that always owns its sound-making looping Audio using Audio:cloneTiny().)
---@param loop boolean
function Audio:setLooping(loop)
end

--- Changes the options for any audio that's already playing (does not affect audio played from the next call to `play()`)
---@param options Sounding.AudioOptions
---@param rootAudio? Sounding.Audio
function Audio:setDynamicOptions(options, rootAudio)
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

--- Sets an arbitrary value to be associated with the audio under the given key
---@param key string
---@param value any
function Audio:setCustomDataField(key, value)
    self.customData[key] = value
end

--- Returns the value previously assigned to the audio using `setCustomDataField()`
---@param key string
---@return any
function Audio:getCustomDataField(key)
    return self.customData[key]
end

--- Returns a full clone of this instance
---@return Sounding.Audio
function Audio:clone()
    -- Implementing this is pointless because Audio is abstract anyway
    -- but oh well
    return setmetatable({}, {__index = Audio})
end

--- Returns the smallest possible viable clone of this instance (omitting some features such as multiple simultaneously playing sources),
--- ideal for when some object needs to own its audio source completely (e.g. looping sounds, heavily dynamically changing sounds, ...)
---@return Sounding.Audio
function Audio:cloneTiny()
    return self:clone()
end

return sounding