

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
   mod:Print("OnEvent(", event, ")")
   local method, id = GetLootMethod()
   if event == "OPEN_MASTER_LOOT_LIST" then
      return module:ShowMenu()
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
      module:PlayerEntry(nil, info, level)
      module:AddSpacer(info)
   elseif level == 2 then
      local submenu = UIDROPDOWNMENU_MENU_VALUE
      if classList[submenu] then
	 module:BuildRaidMenu(info, level, submenu)
      end
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
      local selfLoot 
      if not name then
	 selfLoot = true
	 name = UnitName("player")
      end
      clear(info).value = mod:LootCandidateID(name) -- Master Looter ID
      info.notCheckable = true
      if info.value then
	 if selfLoot then
	    info.text = L["Self Loot"]
	    info.colorCode = "|cffbbbbbb"
	 else
	    info.text = name
	    info.colorCode = CLASS_COLORS[playerClass[name]]
	 end
	 info.func = module.AssignLoot
	 info.arg1 = module
	 info.arg2 = name
      else
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



do
   local data = {}
   function module:AssignLoot(frame, recipient)
      local mlc = mod:LootCandidateID(recipient)
      if not mlc or not LootFrame.selectedSlot then return end
      local icon, name, quantity, quality = GetLootSlotInfo(LootFrame.selectedSlot)
      local link = GetLootSlotLink(LootFrame.selectedSlot)
      if not link then return end
      
      data.id = mlc
      data.name = recipient
      data.link = link
      data.quality = quality

      -- Hook into MagicDKP if present. Check for this static dialog since it indicates a new enough
      -- version of MagicDKP to handle external loot events
      if _G.StaticPopupDialogs["MDKPDuplicate"] then
	 MagicDKP:HandleLoot(recipient, tonumber(match(link, ".*|Hitem:(%d+):")), 1, false, true) -- call MagicDKP
      end
      mod:Print("Should assign ", link, " to ", recipient, " (", mlc, ")")
      GiveMasterLoot(LootFrame.selectedSlot, mlc)
   end
end

function module:ShowMenu()
   ToggleDropDownMenu(1, nil, module.dropdown, "cursor");
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

				   
