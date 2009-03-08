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

local MagicComm = LibStub("MagicComm-1.0")
local GUI = LibStub("AceGUI-3.0")
local LDBIcon = LibStub("LibDBIcon-1.0", true)
local LDB = LibStub("LibDataBroker-1.1", true)

MagicLooterDB = {}

local mod = MagicLooter

local L = LibStub("AceLocale-3.0"):GetLocale("MagicLooter", false)

local UnitGUID = UnitGUID
local sub = string.sub
local tsort = table.sort

local defaultOptions = {
   profile = {
      announceLoot = true,
      autoLootThreshold = 3,
      disenchantThreshold = 3,
      disenchanterList = {},
      bankerList = {},
      minimapIcon = { hide = false }
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
   self.db.RegisterCallback(self, "OnProfileDeleted","OnProfileChanged")
   self.db.RegisterCallback(self, "OnProfileReset", "OnProfileChanged")

   UpdateUpvalues()
   
   if LDB then
      self.ldb =
	 LDB:NewDataObject("MagicLooter",
			   {
			      type =  "launcher", 
			      text = "MagicLooter",
			      icon = "Interface\\Icons\\INV_Helmet_58",
			      tooltiptext = L["|cffffffffMagic Looter|r\n|cffffff00Left click|r to open the configuration pane.\n"],
			      OnClick = function(clickedframe, button)
					   if button == "LeftButton" then
					      mod:ToggleConfigDialog()
					   end
					end,
			   })
      if LDBIcon then
	 LDBIcon:Register("MagicLooter", self.ldb, mod.db.profile.minimapIcon)
      end
   end

   mod.masterLootCandidates = {}
end

function mod:OnEnable()
   mod:RegisterEvent("LOOT_OPENED", "CheckLoot")
   mod:SetupOptions()
end

function mod:OnDisable()
   mod:UnregisterEvent("LOOT_OPENED")
end

function mod:CheckLoot()
   local method, mlparty = GetLootMethod()
   if method ~= "master" or mlparty ~= 0 then
      return -- not using master looter
   end
   for id in pairs(mod.masterLootCandidates) do
      mod.masterLootCandidates[id] = nil
   end

   local numItems = GetNumLootItems()
   local banker, disenchanter, link
   local curslot = 0
   
   -- Build a list of all master loot candidates
   for ci = 1, 40 do
      local candidate = GetMasterLootCandidate(ci)
      if candidate then
	 mod.masterLootCandidates[candidate] = ci
      end
   end

   
   for slot = 1, numItems do
      link =  GetLootSlotLink(slot)
      icon, item, quantity, quality = GetLootSlotInfo(slot)
      if icon and link then
	 local bind = mod:GetBindOn(link)
	 if bind ~= "pickup"  and quality <= db.autoLootThreshold and quality >= GetLootThreshold() then
	    local recipient
	    if mod:IsDisenchantable(link) then
	       if not disenchanter then
		  disenchanter = mod:GetLooterCandidate(db.disenchanterList)
	       end
	       recipient = disenchanter
	       if recipient and db.announceLoot then
		  mod:Print(string.format(L["Auto-looting %s to %s for disenchanting."], link, tostring(GetMasterLootCandidate(recipient))))
	       end
	    else
	       if not banker then
		  banker = mod:GetLooterCandidate(db.bankerList)
	       end	       
	       recipient = banker
	       if recipient and  db.announceLoot then
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

function mod:OnProfileChanged()
   UpdateUpvalues()
   mod:NotifyChange()
end

function mod:GetLootCandidateID(name)
   return mod.masterLootCandidates[name]
end

function mod:GetBankLootCandidateID()
   return mod:GetLooterCandidate(db.bankerList)
end

function mod:GetDisenchantLootCandidateID()
   return mod:GetLooterCandidate(db.disenchanterList)
end


function mod:GetLooterCandidate(list)
   -- Check to see if there's a preferred disenchanter recipient
   local recipient
   for _,name in pairs(list) do
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
   if not self.tooltip then mod:TooltipCreate() end
   local tt = self.tooltip
   tt:SetOwner(UIParent, "ANCHOR_NONE")
   tt:SetHyperlink(item)
   if MagicLooterTooltip:NumLines() > 1  and MagicLooterTooltipTextLeft2:GetText() then
      local t = MagicLooterTooltipTextLeft2:GetText()
      tt:Hide()
      if t == ITEM_BIND_ON_PICKUP then
	 return "pickup"
      elseif t == ITEM_BIND_ON_EQUIP then
	 return "equip"
      elseif t == ITEM_BIND_ON_USE then
	 return "use"
      end
   end
   tt:Hide()
   return nil
end
