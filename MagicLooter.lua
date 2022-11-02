--[[
**********************************************************************
MagicLooter - autodistribute loot with Master Loot mode
**********************************************************************
This file is part of MagicLooter, a World of Warcraft Addon

MagicLooter is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

MagicLooter is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public License
along with MagicLooter.  If not, see <http://www.gnu.org/licenses/>.
**********************************************************************
]]

local MINOR_VERSION = tonumber(("$Revision$"):match("%d+"))

MagicLooter = LibStub("AceAddon-3.0"):NewAddon("MagicLooter", "AceConsole-3.0",
        "AceEvent-3.0", "AceTimer-3.0")
MagicLooter.MAJOR_VERSION = "MagicLooter-1.0"
MagicLooter.MINOR_VERSION = MINOR_VERSION

local GUI = LibStub("AceGUI-3.0")
local LDBIcon = LibStub("LibDBIcon-1.0", true)
local LDB = LibStub("LibDataBroker-1.1", true)

MagicLooterDB = {}

local mod = MagicLooter

local L = LibStub("AceLocale-3.0"):GetLocale("MagicLooter", false)

local UnitGUID = UnitGUID
local tsort = table.sort
local gsub = string.gsub

local db

local defaultOptions = {
    profile = {
        announceLoot = true,
        autoLootThreshold = 3,
        disenchantThreshold = 3,
        disenchanterList = {},
        autoloot = true,
        bankerList = {},
        minimapIcon = { hide = false },
        modules = {}
    }
}

local playerName = UnitName("player")

local function UpdateUpvalues()
    db = mod.db.profile         -- profile data
end

function mod:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("MagicLooterDB", defaultOptions, "Default")
    self.db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
    self.db.RegisterCallback(self, "OnProfileCopied", "OnProfileChanged")
    self.db.RegisterCallback(self, "OnProfileReset", "OnProfileChanged")

    UpdateUpvalues()
    mod:NotifyChange()

    if LDB then
        self.ldb = LDB:NewDataObject("MagicLooter",
                {
                    type = "launcher",
                    text = "MagicLooter",
                    icon = "Interface\\Icons\\INV_Helmet_58",
                    tooltiptext = L["|cffffffffMagic Looter|r\n|cffffff00Left click|r to open the configuration pane.\n"],
                    OnClick = function(clickedframe, button)
                        if button == "LeftButton" then
                            mod:ToggleConfigDialog()
                        else
                            mod:OpenConfigMenu()
                        end
                    end,
                })
        if LDBIcon then
            LDBIcon:Register("MagicLooter", self.ldb, mod.db.profile.minimapIcon)
        end
    end

    mod.masterLootCandidates = {}
    mod.sortedLootCandidates = {}

    mod:SetupOptions()
end

function mod:GetModuleDatabase(module, default, options)
    local optionPane
    defaultOptions.profile.modules[module] = default
    self.db:RegisterDefaults(defaultOptions)
    if options then
        optionPane = mod:RegisterModuleOptions(module, options)
    end
    return db.modules[module], optionPane
end

function mod:OnEnable()
    mod:RegisterEvent("LOOT_OPENED", "CheckLoot")
    mod:RegisterEvent("LOOT_CLOSED", "ClearLoot")
end

function mod:OnDisable()
    mod:UnregisterEvent("LOOT_OPENED")
    mod:UnregisterEvent("LOOT_CLOSED")
end

function mod:ClearLoot()
    mod.banker = nil
    mod.disenchanter = nil
    for id in pairs(mod.masterLootCandidates) do
        mod.masterLootCandidates[id] = nil
    end
    for id in pairs(mod.sortedLootCandidates) do
        mod.sortedLootCandidates[id] = nil
    end
end

function mod:CheckLoot()
    local method, mlparty = GetLootMethod()
    if method ~= "master" or mlparty ~= 0 then
        return
    end -- not using master looter

    -- Build a list of all master loot candidates
    for ci = 1, 40 do
        local candidate = GetMasterLootCandidate(ci)
        if candidate then
            mod.masterLootCandidates[candidate] = ci
            mod.sortedLootCandidates[#mod.sortedLootCandidates + 1] = candidate
        end
    end
    tsort(mod.sortedLootCandidates)
    if db.autoloot then
        for slot = 1, GetNumLootItems() do
            local link = GetLootSlotLink(slot)
            if link then
                local _, _, _, quality = GetLootSlotInfo(slot)
                local bind = mod:GetBindOn(link)
                if bind ~= "pickup" and quality <= db.autoLootThreshold and quality >= GetLootThreshold() then
                    local recipient
                    if mod:IsDisenchantable(link) then
                        recipient = mod:GetDisenchantLootCandidateID()
                        if db.announceLoot then
                            mod:Print(string.format(L["Auto-looting %s to %s for disenchanting."], link, tostring(GetMasterLootCandidate(recipient))))
                        end
                    else
                        recipient = mod:GetBankLootCandidateID()
                        if recipient and db.announceLoot then
                            mod:Print(string.format(L["Auto-looting %s to %s for banking."], link, tostring(GetMasterLootCandidate(recipient))))
                        end
                    end
                    if not recipient then
                        mod:Print(L["Warning: No recipient found?"])
                    else
                        GiveMasterLoot(slot, recipient)
                    end
                end
            end
        end
    end
end

function mod:OnProfileChanged()
    UpdateUpvalues()
    mod:NotifyChange()
    for name, module in mod:IterateModules() do
        if db.modules[name] and module.OnProfileChanged then
            module:OnProfileChanged(db.modules[name])
        end
    end
end

local function GetLootCandidateFromList(list)
    -- Check to see if there's a preferred disenchanter recipient
    local recipient
    for _, name in pairs(list) do
        if mod.masterLootCandidates[name] then
            recipient = mod.masterLootCandidates[name]
            break
        end
    end

    -- No preferred looter found, fall back to the player
    if not recipient then
        recipient = mod.masterLootCandidates[playerName]
    end
    return recipient
end

function mod:GetLootCandidateID(name)
    return mod.masterLootCandidates[name]
end

function mod:GetBankLootCandidateID()
    if not mod.banker then
        mod.banker = GetLootCandidateFromList(db.bankerList)
    end
    return mod.banker
end

function mod:GetDisenchantLootCandidateID()
    if not mod.disenchanter then
        mod.disenchanter = GetLootCandidateFromList(db.disenchanterList)
    end
    return mod.disenchanter
end

function mod:GetRandomLootCandidate()
    local count = #mod.sortedLootCandidates
    if count == 0 then
        return
    end
    local looter = mod.sortedLootCandidates[math.random(count)]
    return looter, mod.masterLootCandidates[looter]
end

function mod:IterateMasterLootCandidates()
    return pairs(mod.masterLootCandidates)
end

-- Return whether the item can be disenchanted or not
function mod:IsDisenchantable(link)
    local _, _, rarity, _, _, type, _, _, equipLoc = GetItemInfo(link)
    return rarity <= db.disenchantThreshold  -- below our threshold for items to disenchant
            and equipLoc  -- is equippable
            and (type == 'Armor' or type == 'Weapon') -- weapon or armor
end


-- Code below to scan the tooltip to find if an item is BoP or not
function mod:TooltipCreate()
    local tt = CreateFrame("GameTooltip", "MagicLooterTooltip", UIParent, "GameTooltipTemplate")
    mod.tooltip = tt
end

function mod:GetBindOn(item)
    if not self.tooltip then
        mod:TooltipCreate()
    end
    local tt = self.tooltip
    tt:SetOwner(UIParent, "ANCHOR_NONE")
    tt:SetHyperlink(item)
    if MagicLooterTooltip:NumLines() > 1 and MagicLooterTooltipTextLeft2:GetText() then
        local t, t2 = MagicLooterTooltipTextLeft2:GetText(), MagicLooterTooltipTextLeft3:GetText()
        tt:Hide()
        if t == ITEM_BIND_ON_PICKUP or t2 == ITEM_BIND_ON_PICKUP then
            return "pickup"
        elseif t == ITEM_BIND_ON_EQUIP or t2 == ITEM_BIND_ON_EQUIP then
            return "equip"
        elseif t == ITEM_BIND_ON_USE or t2 == ITEM_BIND_ON_USE then
            return "use"
        end
    end
    tt:Hide()
    return nil
end

function mod:tokenize(str, values)
    for k, v in pairs(values) do
        str = gsub(str, "%[" .. k .. "%]", (type(v) == "function" and v() or v))
    end
    return str
end

do
    local tableStore = {}
    function mod.clear(tbl)
        if type(tbl) == "table" then
            for id, data in pairs(tbl) do
                if type(data) == "table" then
                    mod.del(data)
                end
                tbl[id] = nil
            end
        end
        return tbl
    end

    function mod.get()
        return {} -- tremove(tableStore) or {}
    end

    function mod.del(tbl, index)
        local todel = tbl
        if index then
            todel = tbl[index]
        end
        if type(todel) ~= "table" then
            return
        end
        mod.clear(todel)
        --      tinsert(tableStore, todel)
        if index then
            tbl[index] = nil
        end
    end
end

function mod:SendChatMessage(message, destination)
    if destination == "RW" then
        destination = (IsRaidLeader() or IsRaidOfficer()) and "RAID_WARNING" or "GROUP"
    end
    if destination == "GROUP" then
        destination = GetNumRaidMembers() > 0 and "RAID" or "PARTY"
    end
    SendChatMessage(message, destination)
end
