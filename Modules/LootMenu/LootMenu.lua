

local mod = MagicLooter
local module = mod:NewModule("LootMenu", "AceHook-3.0", "AceEvent-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("MagicLooter", false)

local tsort = table.sort
local fmt = string.format
local floor = math.floor
local match = string.match

local CLASS_COLORS = {}
local players, playerClass = {}, {}
local classList = {}

local classOrder = {  "DEATHKNIGHT", "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" } 

function module:OnInitialize()
   -- the main drop down menu
   local color = "|cff%2x%2x%2x"
   module.dropdown = CreateFrame("Frame", "ML_LootMenuDropdown", nil, "UIDropDownMenuTemplate")
   module:InitializeDropdown()
   for class, c in pairs(RAID_CLASS_COLORS) do
      CLASS_COLORS[class] = color:format(floor(c.r*255), floor(c.g*255), floor(c.b*255))
   end
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
   --   mod:Print("OnEvent(", event, ")")
   local method, id = GetLootMethod()
   if event == "OPEN_MASTER_LOOT_LIST" then
      return module:ShowMenu()
   elseif event == "LOOT_CLOSED" then
      CloseDropDownMenus() 
   elseif event == "UPDATE_MASTER_LOOT_LIST" then
--      return module.dewdrop:Refresh(1)
   end
end

function module:InitializeDropdown()
   UIDropDownMenu_Initialize(module.dropdown, module.Dropdown_OnLoad, "MENU");
end

function clear(info) for id in pairs(info) do info[id] = nil end return info end

function module:AddSpacer(info)
   clear(info).disabled = true
   UIDropDownMenu_AddButton(info);
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

   module:AddSpacer(info)
end

function module:Dropdown_OnLoad(level)
   if not level then level = 1 end
   local info = UIDropDownMenu_CreateInfo()
   if level == 1 then 
      module:InsertLootItem(info)
      if GetNumRaidMembers() > 0 then
	 module:BuildRaidMenu(info, level)
      else
	 module:BuildPartyMenu(info, level)
      end
      module:AddSpacer(info)
      module:BuildQuickLoot(info, level)
   elseif level == 2 then
      local submenu = UIDROPDOWNMENU_MENU_VALUE
      if submenu == "QUICKLOOT" then
	 module:BuildQuickLoot(info, level)
      elseif classList[submenu] then
	 module:BuildRaidMenu(info, level, submenu)
      end
   end
end

function module:BuildQuickLoot(info, level)
   if level == 1 then
      clear(info).value = "QUICKLOOT"
      info.text = L["Quick Loot"]
      info.hasArrow = true
      info.notCheckable = true
      UIDropDownMenu_AddButton(info, level);
   else
      module:PlayerEntry("_self", info, level)
      module:PlayerEntry("_banker", info, level)
      module:PlayerEntry("_disenchant", info, level)
   end
end

function module:BuildPartyMenu(info, level)
   for _,name in pairs(players) do
      module:PlayerEntry(name, info, level)
   end
end


function module:BuildRaidMenu(info, level, class)
   if not class then 
      for _,class in pairs(classOrder) do
	 if classList[class] then
	    module:ClassMenu(class, info, level)
	 end

      end
   else
      for _,name in pairs(players) do
	 if playerClass[name] == class then
	    module:PlayerEntry(name, info, level)
	 end
      end
   end
end

do
   local disabledFormat =  "|cff7f7f7f%s|r" 
   function module:PlayerEntry(name, info, level)
      local text, color, mlc
      clear(info)

      if name == "_self" then
	 name = UnitName("player")
	 info.text = L["Self Loot"]
	 info.colorCode = "|cffcfffcf"
      elseif name == "_banker" then
	 info.text = L["Bank Loot"]
	 info.colorCode = "|cffcfcfff"
	 mlc = mod:GetBankLootCandidateID()
      elseif name == "_disenchant" then
	 info.text = L["Disenchant Loot"]
	 info.colorCode = "|cffffcfcf"
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
      UIDropDownMenu_AddButton(info, level);
   end

   function module:ClassMenu(class, info, level)
      clear(info).value = class
      info.text = classList[class]
      info.colorCode = CLASS_COLORS[class]
      info.value = class
      info.hasArrow = true
      info.notCheckable = true
      UIDropDownMenu_AddButton(info, level);
   end
end



function module:AssignLoot(frame, recipient)
   local mlc, isBank, isDE
   if recipient == "_banker" then
      isBank = true
      mlc = mod:GetBankLootCandidateID()
      recipient = GetMasterLootCandidate(mlc)
   elseif recipient == "_disenchant" then
      isDE = true
      mlc = mod:GetDisenchantLootCandidateID()
      recipient = GetMasterLootCandidate(mlc)
   else
      mlc = mod:GetLootCandidateID(recipient)
   end
   if not mlc or not LootFrame.selectedSlot then return end
   local icon, name, quantity, quality = GetLootSlotInfo(LootFrame.selectedSlot)
   local link = GetLootSlotLink(LootFrame.selectedSlot)
   if not link then return end
   
   -- Hook into MagicDKP if present. Check for this static dialog since it indicates a new enough
   -- version of MagicDKP to handle external loot events
   if _G.StaticPopupDialogs["MDKPDuplicate"] then
      MagicDKP:HandleLoot(recipient, tonumber(match(link, ".*|Hitem:(%d+):")), 1, false, true, isBank, isDE) -- call MagicDKP
   end
   if isDE or isBank then
      mod:Print("Giving", link, "to", recipient, "for", isDE and "disenchanting" or "banking")
   else
      mod:Print("Assigned ", link, " to ", recipient)
   end
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

				   
