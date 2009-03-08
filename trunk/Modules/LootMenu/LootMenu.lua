--[[
**********************************************************************
LootMenu - an improved Master Loot menu for Magic Looter
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


local MODULE_NAME = "LootMenu"
local mod = MagicLooter
local module = mod:NewModule(MODULE_NAME, "AceHook-3.0", "AceEvent-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("MagicLooter", false)

local tsort = table.sort
local fmt = string.format
local floor = math.floor
local match = string.match
local gsub = string.gsub

local CLASS_COLORS = {}
local players, playerClass = {}, {}
local classList = {}
local info = {}
local classOrder = {  "DEATHKNIGHT", "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" } 

local defaultOptions = {
   rollTimeout = 20,
   rollLimit = 100,
   randomEnabled = true,
   rollMessage = L["Attention! /roll [limit] for [item]. Ends in [timeout] seconds."],
   lootMessage = L["[player] awarded [item][postfix]."],
}

local db = {}

function module:OnInitialize()
   -- the main drop down menu
   module.dropdown = CreateFrame("Frame", "ML_LootMenuDropdown", nil, "UIDropDownMenuTemplate") 
   UIDropDownMenu_Initialize(module.dropdown, module.Dropdown_OnLoad, "MENU");

   
   -- This sets up a CLASS -> hex color map
   local color = "|cff%2x%2x%2x"
   for class, c in pairs(RAID_CLASS_COLORS) do
      CLASS_COLORS[class] = color:format(floor(c.r*255), floor(c.g*255), floor(c.b*255))
   end
   
   -- register defaults and get db storage from the mothership
   db = mod:GetModuleDatabase(MODULE_NAME, defaultOptions, module.options)
   
   module.rolls = {}

   
end

function module:OnProfileChanged(newdb)
   db = newdb
end

function module:OnEnable()
   -- Hook into the loot frame event handler
   module:SecureHook("LootFrame_OnEvent","OnEvent")
   module:RegisterEvent("RAID_ROSTER_UPDATE", "UpdatePlayers")
   module:RegisterEvent("PARTY_MEMBERS_CHANGED", "UpdatePlayers")
   module:UpdatePlayers()
end


function module:OnDisable()
end

function module:OnEvent(this,event,...)
   local method, id = GetLootMethod()
   if event == "OPEN_MASTER_LOOT_LIST" then
      return module:ShowMenu()
   elseif event == "LOOT_CLOSED" then
      CloseDropDownMenus() 
   elseif event == "UPDATE_MASTER_LOOT_LIST" then
--      return module.dewdrop:Refresh(1)
   end
end

function clear() for id in pairs(info) do info[id] = nil end return info end

function module:AddSpacer(level)
   clear().disabled = true
   UIDropDownMenu_AddButton(info, level);
end

function module:InsertLootItem(info)
   if not LootFrame.selectedSlot then return end
   local icon, name, quantity, quality = GetLootSlotInfo(LootFrame.selectedSlot)
--   local tip = self.db.profile.mlitemtip
   local link = GetLootSlotLink(LootFrame.selectedSlot)
   if not link then return nil end
   if quantity > 1 then
      info.text = fmt("%s%s|rx%d", ITEM_QUALITY_COLORS[quality].hex, name, quantity)
   else
      info.text = fmt("%s%s|r", ITEM_QUALITY_COLORS[quality].hex, name)
   end
   info.icon = icon
   info.isTitle = true
   info.notCheckable = true
   UIDropDownMenu_AddButton(info);

   module:AddSpacer()
end

function module:Dropdown_OnLoad(level)
   if not level then level = 1 end
   if level == 1 then 
      module:InsertLootItem(info)
      if GetNumRaidMembers() > 0 then
	 module:BuildRaidMenu(level)
      else
	 module:BuildPartyMenu(level)
      end
      module:AddSpacer()

      module:BuildQuickLoot(level)
      module:BuildRandomLoot(level)
   elseif level == 2 then
      local submenu = UIDROPDOWNMENU_MENU_VALUE
      if submenu == "QUICKLOOT" then
	 module:BuildQuickLoot(level)
      elseif submenu == "RANDOMLOOT" then
	 module:BuildRandomLoot(level)
      elseif classList[submenu] then
	 module:BuildRaidMenu(level, submenu)
      end
   end
end


function module:AddStaticButtons(hash, level)
   if hash[level] then
      for _,button in ipairs(hash[level]) do
	 UIDropDownMenu_AddButton(button, level)
      end
   end
end

-- Add the menu where you can give loot to a random player
-- We can do it via a roll or just randomly give it out
function module:BuildRandomLoot(level)
   if not db.randomEnabled then return end
   module:AddStaticButtons(module.staticMenus.random, level)
   if level == 2 then
      -- add info about roll in progress
      if module.rollTimeout then
	 module:AddSpacer(level)
	 local remaining = module.rollTimeout - time()
	 if remaining > 1 then
	    clear().text = fmt(L["|cff2255ffRolling... |cff44ff44%s|cff2255ff seconds left"], remaining)
	 else
	    clear().text = L["|cff00ffcfRoll completed|r"]
	 end
	 info.isTitle = true
	 info.notCheckable = true
	 info.icon = "Interface\\Icons\\Ability_Hunter_Readiness"
	 UIDropDownMenu_AddButton(info, level)
      end
      if next(module.rolls) then
	 local sorted = {}
	 local mlcs = mod.masterLootCandidates
	 local haveNonMLC
	 for name in pairs(module.rolls) do
	    sorted[#sorted+1] = name
	    if not mlcs[name] then
	       haveNonMLC = true
	    end
	 end
	 tsort(sorted, function(a, b) return
			  module.rolls[a] > module.rolls[b]
		       end)
	 for _,name in ipairs(sorted) do
	    if UnitExists(name) and mlcs[name] then
	       module:PlayerEntry(name, level, true)
	       info.text = string.format("% 4d: %s", module.rolls[name], info.text)
	       UIDropDownMenu_AddButton(info, level);
	    end
	 end
	 if haveNonMLC then
	    module:AddSpacer(level)
	    module:AddStaticButtons(module.staticMenus.rollFail, level)
	    for _,name in ipairs(sorted) do
	       if UnitExists(name) and not mlcs[name] then
		  module:PlayerEntry(name, level, true)
		  info.text = string.format("% 4d: %s", module.rolls[name], info.text)
		  UIDropDownMenu_AddButton(info, level);
	       end
	    end
	 end
      end
   end
end


function module:BuildQuickLoot(level)
   if level == 1 then
      clear().value = "QUICKLOOT"
      info.text = L["Quick Loot"]
      info.hasArrow = true
      info.notCheckable = true
      UIDropDownMenu_AddButton(info, level);
   else
      module:PlayerEntry("_self", level)
      module:PlayerEntry("_banker", level)
      module:PlayerEntry("_disenchant", level)
   end
end

function module:BuildPartyMenu(level)
   for _,name in pairs(players) do
      module:PlayerEntry(name, level)
   end
end


function module:BuildRaidMenu(level, class)
   if not class then 
      for _,class in pairs(classOrder) do
	 if classList[class] then
	    module:ClassMenu(class, level)
	 end

      end
   else
      for _,name in pairs(players) do
	 if playerClass[name] == class then
	    module:PlayerEntry(name, level)
	 end
      end
   end
end

do
   local disabledFormat =  "|cff7f7f7f%s|r" 
   function module:PlayerEntry(name, level, buildOnly)
      local text, color, mlc
      clear()

      if name == "_self" then
	 name = UnitName("player")
	 info.text = L["Self Loot"]
      elseif name == "_banker" then
	 info.text = L["Bank Loot"]
	 mlc = mod:GetBankLootCandidateID()
      elseif name == "_disenchant" then
	 info.text = L["Disenchant Loot"]
	 mlc = mod:GetDisenchantLootCandidateID()
      else
	 info.text = name
	 info.colorCode = CLASS_COLORS[playerClass[name]]
      end

      if not mlc then
	 mlc = mod:GetLootCandidateID(name) -- Master Looter ID
      end

      info.notCheckable = true
      if mlc then
	 -- this dude can loot
	 info.func = module.AssignLoot
	 info.arg1 = module
	 info.arg2 = name
      else
	 -- non-applicable recipient
	 info.notClickable = true
	 info.text = disabledFormat:format(name)
      end
      if not buildOnly then
	 UIDropDownMenu_AddButton(info, level);
      end
   end

   function module:ClassMenu(class, level)
      clear().value = class
      info.text = classList[class]
      info.colorCode = CLASS_COLORS[class]
      info.value = class
      info.hasArrow = true
      info.notCheckable = true
      UIDropDownMenu_AddButton(info, level);
   end
end

function module:AssignLoot(frame, recipient)
   local mlc, isBank, isDE, isRandom
   if recipient == "_banker" then
      isBank = true
      mlc = mod:GetBankLootCandidateID()
      recipient = GetMasterLootCandidate(mlc)
   elseif recipient == "_disenchant" then
      isDE = true
      mlc = mod:GetDisenchantLootCandidateID()
      recipient = GetMasterLootCandidate(mlc)
   else
      if not recipient then
	 recipient, mlc = mod:GetRandomLootCandidate()
	 isRandom = true
      else
	 mlc = mod:GetLootCandidateID(recipient)
      end
   end
   if not mlc or not LootFrame.selectedSlot then return end
   local icon, name, quantity, quality = GetLootSlotInfo(LootFrame.selectedSlot)
   local link = GetLootSlotLink(LootFrame.selectedSlot)
   if not link then return end
   
   -- Hook into MagicDKP if present. Check for this static dialog since it indicates a new enough
   -- version of MagicDKP to handle external loot events. Only call if we have more than 5 players,
   -- which would indicate a raid.
   if _G.StaticPopupDialogs["MDKPDuplicate"] and #players > 5 then
      MagicDKP:HandleLoot(recipient, tonumber(match(link, ".*|Hitem:(%d+):")), 1, false, true, isBank, isDE) -- call MagicDKP
   end
   clear().player = recipient
   info.item = link
   info.postfix = (isDE and L[" for disenchanting"]) or (isBank and L[" for the guild bank"]) or (isRandom and L[" from a random roll"]) or  "" 
   mod:Print(mod:tokenize(db.lootMessage, info))
   GiveMasterLoot(LootFrame.selectedSlot, mlc)
end


function module:ShowMenu()
   ToggleDropDownMenu(1, nil, module.dropdown, "cursor");
   return true
end

do
   local party_units = { "player", "party1", "party2", "party3", "party4" }
   function module:UpdatePlayers()
      for id in ipairs(players) do players[id] = nil end
      for id in ipairs(playerClass) do playerClass[id] = nil end
      for id in ipairs(classList) do classList[id] = nil end
      
      local id, name, class, className
      if GetNumRaidMembers() > 0 then
	 for id = 1,GetNumRaidMembers() do
	    name, _, _, _, className, class = GetRaidRosterInfo(id)
	    players[#players+1]  = name
	    playerClass[name] = class
	    classList[class] = className
	 end
      else
	 for _,unit in ipairs(party_units) do
	    if UnitExists(unit) then
	       name = UnitName(unit)
	       className, class = UnitClass(unit)
	       players[#players + 1] = name
	       playerClass[name] = class
	       classList[class] = className
	    end
	 end
      end
      tsort(players)
   end
end
local rollPattern = gsub(gsub(gsub(RANDOM_ROLL_RESULT, "[()]", "."), "%%s", "([^ ]+)") , "%%d", "(%%d+)")

function module:ParseRollChat(event, message)
   if not module.rollTimeout or module.rollTimeout < time() then
      -- not rolling or too late
      module:UnregisterEvent("CHAT_MSG_SYSTEM")
      return 
   end
   local player, roll, min, max = match(message, rollPattern)
   if player then
      roll, min, max = tonumber(roll), tonumber(min), tonumber(max)
      if  min == 1 and max == db.rollLimit and not module.rolls[player] then
	 module.rolls[player] = roll
      end
   end
end


function module:EndRoll()
   for id in pairs(module.rolls) do
      module.rolls[id] = nil
   end
   module.rollTimeout = nil
end

function module:StartNewRoll()
   local link = LootFrame.selectedSlot and GetLootSlotLink(LootFrame.selectedSlot)
   if not link then return end
   module:EndRoll()
   module:RegisterEvent("CHAT_MSG_SYSTEM", "ParseRollChat")
   module.rollTimeout = time() + db.rollTimeout
   clear().limit = db.rollLimit
   info.item = link
   info.timeout = db.rollTimeout
   
   mod:SendChatMessage(mod:tokenize(db.rollMessage, info), "RW")
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

function module:SetProfileParam(var, value)
   local varName = var[#var]
   db[varName] = value
end

function module:GetProfileParam(var) 
   local varName = var[#var]
   return db[varName]
end

function module:AnnounceDisabled()
   return not db.announceLoot
end

function module:RandomDisabled()
   return not db.randomEnabled
end


module.staticMenus = {
   random = {
      {
	 { 
	    value = "RANDOMLOOT",
	    text = L["Random"],
	    hasArrow = true,
	    notCheckable = true,
	 }
      }, 
      {
	 { 
	    text = L["Give to random player"],	
	    func = module.AssignLoot,
	    arg1 = module,
	    icon = "Interface\\Buttons\\UI-GroupLoot-Dice-Up",
	    notCheckable = true,
	 },
	 {
	    text = L["Clear list and announce new roll"],
	    icon = "Interface\\Buttons\\UI-GuildButton-MOTD-Up",
	    func = module.StartNewRoll,
	    arg1 = module,
	    notCheckable = true,
	 },
      }
   },
   rollFail = {
      [2] = {
	 { 
	    text = L["Not on ML List:"],
	    notCheckable = true,
	    isTitle = true,
	 }
      }
   }
}


-- config options
module.options = {
   type = "group",
   name = L["Loot Menu"],
   handler = module,
   set = "SetProfileParam",
   get = "GetProfileParam", 
   args = {
      randomEnabled = {
	 type = "toggle",
	 name = L["Enable Random Menu"],
	 desc = L["Show the randon loot distribution menu. "],
	 order = 10,
      }, 
      rollTimeout = {
	 type = "range",
	 name = L["Random Roll Timeout"],
	 desc = L["Time in seconds before the random roll expires."],
	 min = 5, max = 120, step = 1,
	 order = 20,
	 width="full",
	 disabled = "RandomDisabled",
      },
      rollLimit = {
	 type = "range", 
	 name = L["Random Roll Limit"],
	 desc = L["The upper limit for random rolls. The default is 100."],
	 min = 5, max = 10000, step = 1,
	 width="full",
	 order = 30,
	 disabled = "RandomDisabled",
      },
      rollMessage = {
	 type = "input",
	 width="full",
	 name = L["Random Roll Message"],
	 desc = L["The message sent to the raid or party when a new roll begins. The following tokens are available: [limit] (upper limit of roll), [item] (the item link) and [timeout] (the roll timeout)."],
	 order = 40,
	 disabled = "RandomDisabled",
      },
      announceLoot = {
	 type = "toggle",
	 name = L["Announce Loot Recipients"],
	 desc = L["Print a massage, only visible by you, when Magic Looter autoloots an item."],
	 order = 100, 
	 width="full",
      },
      lootMessage = {
	 type = "input",
	 name = L["Loot Announce Message"],
	 desc = L["The message sent when an item is looted. The following tokens are available: [player] (receiving player), [item] (the item link) and [postfix (optional postfix for disenchanted, banked or randomly distributed loot)."],
	 order = 110,
	 width="full",
	 disabled = "AnnounceDisabled",
      },
   }
}
