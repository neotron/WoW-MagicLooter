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

local mod = MagicLooter
local L = LibStub("AceLocale-3.0"):GetLocale("MagicLooter", false)
local AC = LibStub("AceConfig-3.0")
local ACD = LibStub("AceConfigDialog-3.0")
local DBOpt = LibStub("AceDBOptions-3.0")
local R = LibStub("AceConfigRegistry-3.0")

local LDBIcon = LibStub("LibDBIcon-1.0", true)
local LDB = LibStub("LibDataBroker-1.1", true)

local options

local function UpdateUpvalues()
   db = mod.db.profile         -- profile data
end

function mod:NotifyChange()
   UpdateUpvalues()
   R:NotifyChange(L["Magic Looter"])
end


local lootThresholds = {
   L["Uncommon"],
   L["Rare"],
   L["Epic"], 
}

-- config options
options = {
   type = "group",
   name = L["Options"],
   handler = mod,
   set = "SetProfileParam",
   get = "GetProfileParam", 
   args = {
      autoLootThreshold = {
	 type = "select",
	 name = L["Auto Loot Threshold"],
	 desc = L["Only auto loot items below and including the selected rarity."],
	 values = lootThresholds, 
	 order = 1, 
      }, 
      disenchantThreshold = {
	 type = "select",
	 name = L["Disenchant Threshold"],
	 desc = L["Only consider items at or below this threshold as disenchantable. Items not considered disenchantable will be auto looted using the banker list instead of the disenchanter list."],
	 values = lootThresholds, 
	 order = 1, 
      },
      spacer1 = {
	 type = "description",
	 name = "",
	 width = "full",
	 order = 5, 
      },
      disenchanterList = {
	 type = "input",
	 multiline = true,
	 name = L["Disenchanter Priority List"],
	 desc = L["A newline separated list of disenchanters. All disenchantable loot will be given to the people on the list in the order they appear. If none of the names are valid loot targets, the loot will be given to the player."],
	 order = 10, 
      },
      bankerList = {
	 type = "input",
	 multiline = true,
	 name = L["Banker Priority List"],
	 desc = L["A newline separated list of bankers. All loot that isn't disenchantable will be given to the people on the list in the order they appear. If none of the names are valid loot targets, the loot will be given to the player."],
	 order = 10,
      },
      spacer2 = {
	 type = "description",
	 name = "",
	 width = "full",
	 order = 20
      },
      minimapIcon = {
	 type = "toggle",
	 name = L["Enable Minimap Icon"],
	 desc = L["Show an icon to open the Magic Looter config at the minimap."],
	 get = function() return not db.minimapIcon.hide end,
	 set = function(info, value) db.minimapIcon.hide = not value LDBIcon[value and "Show" or "Hide"](LDBIcon, "MagicLooter") end,
	 disabled = function() return not LDBIcon end,
      },
      announceLoot = {
	 type = "toggle",
	 name = L["Announce Loot Recipients"],
	 desc = L["Print a massage, only visible by you, when Magic Looter autoloots an item."],
      },
      autoloot = {
	 type = "toggle",
	 name = L["Enable Auto Loot"],
	 desc = L["Automatically loot items for disenchanting and banking if they fall within the specified thresholds. If disabled, you can still use the smart looting using the MagicLooter Loot Menu addon."],
      },
   }
}

function mod:SetProfileParam(var, value)
   local varName = var[#var]
   if varName == "autoLootThreshold" or varName == "disenchantThreshold" then
      value = value + 1
   elseif varName == "disenchanterList" or varName == "bankerList" then
      local newValues = {}
      for _,player in ipairs(  { strsplit("\n", value) } ) do 
	 player = player:lower():trim():gsub("^.", string.upper)
	 if strlen(player) then
	    newValues[#newValues + 1] = player
	 end
      end
      value = newValues
   end
      
   db[varName] = value
end

function mod:GetProfileParam(var) 
   local varName = var[#var]
   if varName == "autoLootThreshold" or varName == "disenchantThreshold" then
      return db[varName] - 1
   elseif varName == "disenchanterList" or varName == "bankerList" then
      return strjoin("\n", unpack(db[varName]))
   end
   return db[varName]
end

function mod:SetProfileParam(var, value)
   local varName = var[#var]
   if varName == "autoLootThreshold" or varName == "disenchantThreshold" then
      value = value + 1
   elseif varName == "disenchanterList" or varName == "bankerList" then
      local newValues = {}
      for _,player in ipairs(  { strsplit("\n", value) } ) do 
	 player = player:lower():trim():gsub("^.", string.upper)
	 if strlen(player) > 0 then
	    newValues[#newValues + 1] = player
	 end
      end
      value = newValues
   end
      
   db[varName] = value
end

function mod:GetProfileParam(var) 
   local varName = var[#var]
   if varName == "autoLootThreshold" or varName == "disenchantThreshold" then
      return db[varName] - 1
   elseif varName == "disenchanterList" or varName == "bankerList" then
      return strjoin("\n", unpack(db[varName]))
   end
   return db[varName]
end


function mod:OptReg(optname, tbl, dispname, cmd)
   local regtable
   if dispname then
      optname = "Magic Looter"..optname
      AC:RegisterOptionsTable(optname, tbl, cmd)
      if not cmd then
	 regtable = ACD:AddToBlizOptions(optname, dispname, L["Magic Looter"])
      end
   else
      AC:RegisterOptionsTable(optname, tbl, cmd)
      if not cmd then
	 regtable = ACD:AddToBlizOptions(optname, L["Magic Looter"])
      end
   end
   return regtable
end

function mod:RegisterModuleOptions(module, options)
   return mod:OptReg(": "..module, options, options.name)
end

function mod:SetupOptions()
   mod.configFrame = mod:OptReg("Magic Looter", options)
   mod.profileFrame = mod:OptReg(": Profiles", DBOpt:GetOptionsTable(mod.db), L["Profiles"])
   mod:OptReg("Magic Looter CmdLine", {
		 name = "Command Line",
		 type = "group",
		 args = {
		    config = {
		       type = "execute",
		       name = L["Show configuration dialog"],
		       func = function() mod:ToggleConfigDialog() end,
		       dialogHidden = true
		    },
		 }
	      }, nil,  { "mloot", "magiclooter" })
end

function mod:OpenConfigMenu()
--   LibStub("LibDropdown-1.0"):OpenAce3Menu(options)
end

function mod:ToggleConfigDialog()
   InterfaceOptionsFrame_OpenToCategory(mod.profileFrame)
   InterfaceOptionsFrame_OpenToCategory(mod.configFrame)
end
