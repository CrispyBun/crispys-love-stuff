--- The library - Calling is equivalent to `latl.get()`.
---@overload fun(prompt: string, langcode: string?): string
local latl = {}
local latlMT = {}

latl.currentLanguage = "en_US"

---@type Latl.LanguageList
latl.langs = {}

--------------------------------------------------
--- Definitions

---@class Latl.LanguageList
---@field [string] Latl.Language Each language code (e.g. "en_US") mapped to its language definition

--- A set of translations
---@class Latl.Language
---@field [string] string Each text identifier (e.g. "game.items.sword") mapped to its translation (e.g. "Sword")

--------------------------------------------------
--- Getting translations

--- Gets the translation of the given `prompt`. Will use `latl.currentLanguage` if `langcode` isn't provided.
--- You can also call this function using `latl()`.
---@param prompt string The identifier of the translation (e.g. "game.items.sword")
---@param langcode? string
---@return string
function latl.get(prompt, langcode)
    if not prompt then error("No text prompt provided", 2) end
    langcode = langcode or latl.currentLanguage

    local language = latl.langs[langcode]
    if not language then return prompt end

    local translation = language[prompt]
    if not translation then return prompt end

    return translation
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
function latl.setCurrentLanguage(langcode)
    latl.currentLanguage = langcode
end

--------------------------------------------------
---@diagnostic disable-next-line: param-type-mismatch
return setmetatable(latl, latlMT)