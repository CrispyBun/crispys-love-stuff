--- The library - Calling is equivalent to `latl.get()`.
---@overload fun(prompt: string, langcode: string?): string
local latl = {}
local latlMT = {}

--- The currently selected language used as default when getting translations
latl.currentLanguage = "en_US"

--- All of the defined languages
---@type Latl.LanguageList
latl.langs = {}

--------------------------------------------------
--- Definitions

---@class Latl.LanguageList
---@field [string] Latl.Language Each language code (e.g. `"en_US"`) mapped to its language definition

---@class Latl.Language
---@field fields table<string, string> Each text identifier (e.g. `"game.items.sword"`) mapped to its translation (e.g. `"Sword"`)
local Language = {}
local LanguageMT = {__index = Language}

--------------------------------------------------
--- Getting translations

--- Gets the translation of the given `prompt`. Will use `latl.currentLanguage` if `langcode` isn't provided.
--- You can also call this function using `latl()`.
---@param prompt string The identifier of the translation (e.g. `"game.items.sword"`)
---@param langcode? string
---@return string
function latl.get(prompt, langcode)
    if not prompt then error("No text prompt provided", 2) end
    langcode = langcode or latl.currentLanguage

    local language = latl.langs[langcode]
    if not language then return prompt end

    return language:get(prompt)
end

---@param t any
---@param prompt string
---@param langcode? string
---@return string
function latlMT.__call(t, prompt, langcode)
    return latl.get(prompt, langcode)
end

--- Sets the currently selected language.
---@param langcode string
function latl.setLanguage(langcode)
    latl.currentLanguage = langcode
end

--------------------------------------------------
--- Defining translations

--- Adds a single translation to the specified language.
---@param langcode string The language code of the language (e.g. `"en_US"`)
---@param textID string The identifier of the translation (e.g. `"game.items.sword"`)
---@param translation string The translation itself (e.g. `"Sword"`)
function latl.addTranslation(langcode, textID, translation)
    local language = latl.langs[langcode] or latl.newLanguage()
    latl.langs[langcode] = language

    language.fields[textID] = translation
end

--------------------------------------------------
--- The Language class

--- Creates a new language object. Use this if you want to manage the language objects yourself,
--- otherwise this is used internally and you don't have to worry about it.
---@return Latl.Language
function latl.newLanguage()
    ---@type Latl.Language
    local language = {
        fields = {}
    }
    return setmetatable(language, LanguageMT)
end

--- Returns the translation of the given `prompt`.
---@param prompt string
---@return string
function Language:get(prompt)
    local translation = self.fields[prompt]
    if not translation then return prompt end

    return translation
end

--------------------------------------------------
---@diagnostic disable-next-line: param-type-mismatch
return setmetatable(latl, latlMT)