--[[
**********************************************************************
DKPBidder - Take DKP bids from the master loot menu.
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

local MODULE_NAME = "DKPBidder"
local mod = MagicLooter
local module = mod:NewModule(MODULE_NAME, "AceEvent-3.0", "AceTimer-3.0")
local LM = mod:GetModule("LootMenu")
local L = LibStub("AceLocale-3.0"):GetLocale("MagicLooter", false)
local tsort = table.sort
local fmt = string.format

local MagicComm = LibStub("MagicComm-1.0")
local defaultOptions = {
   priorities = { "Primary Role", "Secondary Role", "Off Spec" },
   bidTimeout = 60,
   bidMessage = L["Attention: Bidding for [item] now open for [timeout] seconds."],
   bidClosedMessage = L["Bidding for [item] is now closed."],
   bidChannels = {
      CHAT_MSG_WHISPER = true
   },
   allowOverwrite = true,
   allowLowerBid = true,
   autoClose = false,
}
local db = {}
local networkData = {}
local info = {}

-- The channels in which bid whispers might come.
local bidChannels = {
   CHAT_MSG_WHISPER = L["Whisper"],
   CHAT_MSG_RAID = L["Raid"],
   CHAT_MSG_SAY = L["Say"], 
}

function new() for id in pairs(info) do info[id] = nil end return info end

function module:OnInitialize()
   -- register defaults and get db storage from the mothership
   db = mod:GetModuleDatabase(MODULE_NAME, defaultOptions, module.options)
   module.bids = {}
   module.bidders = {}
   module.remainingBidders = {}
end

function module:OnEnable()
   MagicComm:RegisterListener(module, "MD")
   LM:RegisterCustomEntry(module, "AddBidMenu")
end

function module:OnDisable()
   MagicComm:UnregisterListener(module, "MD")
   LM:UnregisterCustomEntry(module)
end

function module:AddBidMenu(level, submenu)
   local staticMenu = module.staticMenu[submenu or "DKPBID"]
   if not staticMenu then return end
   
   LM:AddStaticButtons(staticMenu, level)
   
   if level == 2 then
      local button
      -- add info bid in progress
      if module.bidTimeout then
	 local remaining = module.bidTimeout - time()
	 LM:AddSpacer(level)
	 if db.bidTimeout > 0 then
	    if remaining > 1 then
	       LM:Header(level, fmt(L["|cff2255ffBidding... |cff44ff44%s|cff2255ff seconds left"], remaining), "Interface\\Icons\\Ability_Hunter_Readiness")
	       LM:AddStaticButtons(module.staticMenu.cancelBid, level)
	    else
	       LM:Header(level, L["|cff00ffcfBidding closed|r"], "Interface\\Icons\\Ability_Hunter_Readiness")
	    end
	 elseif remaining > 1 then 
	    LM:Header(level, L["|cff2255ffBidding in progress...|r"], "Interface\\Icons\\Ability_Hunter_Readiness")
	    LM:AddStaticButtons(module.staticMenu.cancelBid, level)
	 else
	    LM:Header(level, L["|cff00ffcfBidding closed|r"], "Interface\\Icons\\Ability_Hunter_Readiness")
	 end
      end
      for priority, bids in pairs(module.bids) do
	 if bids and next(bids) then
	    LM:AddSpacer(level)
	    LM:Header(level, db.priorities[priority] or L["Whisper Bids"])

	    tsort(bids, function(a, b) return (a.bid or 0) > (b.bid or 0) end)
	    
	    for _,data in ipairs(bids) do
	       if UnitExists(data.bidder) then
		  local button = LM:PlayerEntry(data.bidder, level, true)
		  button.text = fmt("% 4d: %s%s", tostring(data.bid), tostring(button.text), data.whisper and fmt(" (%s)", data.whisper) or "")
		  button.arg2 = data
		  UIDropDownMenu_AddButton(button, level);
	       end
	    end
	 end
      end
   end
end

local function SetNetworkData(cmd, data, misc1, misc2, misc3, misc4)
   networkData.cmd = cmd
   networkData.data = data
   networkData.misc1 = misc1
   networkData.misc2 = misc2
   networkData.misc3 = misc3
   networkData.misc4 = misc4
end

function module:SendUrgentMessage(channel, recipient)
   MagicComm:SendUrgentMessage(networkData, "MD", channel, recipient)
end

function module:StartNewBid(override)
   local link = (LootFrame.selectedSlot and GetLootSlotLink(LootFrame.selectedSlot)) or override
   if not link then return end
   module:BidCompleted(true)   
   if db.bidTimeout > 0 then
      module.bidTimeout = time() + db.bidTimeout
   else
      module.bidTimeout = time() + 10000000
   end
      
   module.currentBidItem = link
   mod.clear(module.bids)
   mod.clear(module.bidders)
   mod.clear(module.remainingBidders)
   new().item = link
   info.timeout = db.bidTimeout
   mod:SendChatMessage(mod:tokenize(db.bidMessage, info), "RW")
   module:SendBidRequest(link)
   for channel in pairs(db.bidChannels) do
      module:RegisterEvent(channel, "HandleBidMessage")
   end
   if module.bidTimer then
      module:CancelTimer(module.bidTimer, true)
   end
   if db.bidTimeout > 0 then
      module.bidTimer = module:ScheduleTimer("BidCompleted", db.bidTimeout)
   end
end

function module:BidCompleted(quiet)
   for channel in pairs(bidChannels) do
      module:UnregisterEvent(channel)
   end
   new().item = module.currentBidItem
   if not quiet then 
      mod:SendChatMessage(mod:tokenize(db.bidClosedMessage, info), "GROUP")
   end
   module:CancelTimer(module.bidTimer, true)
   module.bidTimer = nil
   module.bidTimeout = time()
   module.currentBidItem = nil
end

function findpattern(text, pattern, start)
   local a, b = string.find(text, pattern, start)
   if a and b then 
      return string.sub(text, a, b)
   end
end

function module:HandleBidMessage(channel, msg, sender)
   local bid = findpattern(msg, "%d+")
   if not bid then return end
   if mod:GetLootCandidateID(sender) then
      bid = tonumber(bid)
      module.remainingBidders[sender] =  nil
      local bidId = #db.priorities+1
      if not module.bids[bidId] then
	 module.bids[bidId] = mod.get()
      end
      local bidData = module.bidders[sender]
      if bidData then
	 if not db.allowOverwrite then return end
	 if db.allowLowerBid or bid > bidData.bid then
	    bidData.bid = bid
	    bidData.whisper = msg
	 end
      else
	 bidData = mod.get()
	 bidData.bidder = sender
	 bidData.bid    = bid
	 bidData.whisper = msg      
	 module.bids[bidId][#module.bids[bidId]+1] = bidData
	 module.bidders[sender] = bidData
      end
      module:ExtendBid()
   end
   if db.autoClose and #module.remainingBidders == 0 then
      module:BidCompleted()
   end
end

function module:SendBidRequest(item)
   SetNetworkData("DKPBID", item, db.priorities)
   module:SendUrgentMessage("RAID")
end

function module:OnDKPResponse(bidder, bid, priority, item)
   if  (module.bidTimeout or 0) < time() then --  item ~= module.currentBidItem or
      mod:Print("Ignoring late or invalid bid from",bidder,":", bid or "(passed)", "for item", item)
      return
   end
   
   module:ExtendBid()
   if bid == nil then
      -- Passed bid
      module.remainingBidders[bidder]  = nil
--      mod:Print(bidder, "passed on item", item)
   else
      mod:Print(bidder, "bid", bid, "on item", module.currentBidItem, "as", db.priorities[priority])
      local prio = module.bids[priority] or mod.get()
      module.remainingBidders[bidder]  = nil
      if not module.bidders[bidder] then 
	 local data = mod.get()
	 data.bidder = bidder
	 data.bid = bid
	 prio[#prio+1] = data
	 module.bids[priority] = prio
	 module.bidders[bidder] = data
      end
   end
   if db.autoClose and #module.remainingBidders == 0 then
      module:BidCompleted()
   end
end

function module:ExtendBid()
   if db.bidTimeout > 0 and db.bidExtension > 0 then
      local remaining = module.bidTimeout - time()
      if db.bidExtension > remaining then
	 module.bidTimeout  = time() + db.bidExtension
      end
      if module.bidTimer then
	 module:CancelTimer(module.bidTimer, true)
      end
      module.bidTimer = module:ScheduleTimer("BidCompleted", db.bidExtension)
   end
end

function module:SetProfileParam(var, value, sub)
   local varName = var[#var]
   if sub ~= nil then
      if type(db[varName]) ~= "table" then db[varName] = mod.get() end
      db[varName][value] = sub
   else
      if varName == "priorities" then
	 local newValues = mod.get()
	 for _,prio in ipairs(  { strsplit("\n", value) } ) do 
	    prio = prio:trim()
	    if strlen(prio) > 0 then
	       newValues[#newValues + 1] = prio
	    end
	 end
	 value = newValues
	 mod.del(db.varName)
      end
      db[varName] = value
   end
end

function module:GetProfileParam(var, sub)
   local varName = var[#var]
   if sub ~= nil then
      return type(db[varName]) == "table" and db[varName][sub]
   elseif varName == "priorities" then
      return strjoin("\n", unpack(db[varName]))
   else
      return db[varName]
   end
end

function module:OnProfileChanged(newdb)
   db = newdb
end

module.staticMenu = {
   DKPBID = {
      {
	 { 
	    value = "DKPBID",
	    text = L["DKP Bidding"],
	    hasArrow = true,
	    notCheckable = true,
	 }
      }, 
      {
	 {
	    text = L["Clear list and start new bid"],
	    icon = "Interface\\Buttons\\UI-GuildButton-MOTD-Up",
	    func = module.StartNewBid,
	    arg1 = module,
	    notCheckable = true,
	 },
      }
   },
   cancelBid = {
      [2] = {
	 {
	    text = L["Close bidding"],
	    func = module.BidCompleted,
	    arg1 = module,
	    notCheckable = true,
	 }
      }
   }
}

-- config options
module.options = {
   type = "group",
   name = L["DKP Bidder"],
   handler = module,
   set = "SetProfileParam",
   get = "GetProfileParam", 
   args = {
      bidTimeout = {
	 type = "range",
	 name = L["Bid Timeout"],
	 desc = L["Time in seconds before the bid time expires. Set to zero to avoid bid expiration."],
	 min = 0, max = 120, step = 1,
	 order = 20,
	 width="full",
      },
      bidExtension = {
	 type = "range",
	 name = L["Bid Extension"],
	 desc = L["Minimum remaining duration of the bidding after receiving a new bid. This can be used to automatically extend the bid duration after a bid is received. A value of zero disables the feature."],
	 min = 0, max = 60, step = 1,
	 order = 21,
	 width = "full", 
      },
      bidMessage = {
	 type = "input",
	 width="full",
	 name = L["Bid Announce Message"],
	 desc = L["The message sent to the raid or party when a new bid begins. The following token can be used: [item] (the item link) and [timeout] (the bid timeout)."],
	 order = 40,
      },
      bidClosedMessage = {
	 type = "input",
	 width="full",
	 name = L["Bid Close Message"],
	 desc = L["The message sent to the raid or party when the bidding is closed. The following token can be used: [item]."],
	 order = 40,
      },
      bidChannels = {
	 type = "multiselect",
	 values = bidChannels,
	 name = L["Bid Channels"],
	 desc = L["The channels that DKPBidder will listen to bids on. If no channels are selected, only bids sent by MagicDKP_Client will be recorded."], 
	 order = 50, 
      },
      allowOverwrite = {
	 type = "toggle",
	 name = L["Allow Bid Changes"],
	 desc = L["If enabled whisper bids are allowed to overrwrite previous bids. "], 
	 width = "full",
	 order = 60, 
      },
      allowLowerBid= {
	 type = "toggle",
	 name = L["Allow Lowering Bids"],
	 desc = L["If enabled whisper bids are allowed to lower a previous bid. "],
	 hidden = function() return not db.allowOverwrite end, 
	 width = "full", 
	 order = 60, 
      },
      autoClose = {
	 type = "toggle",
	 name = L["Close Bid Automatically "],
	 desc = L["When enabled, bidding will be closed early if everyone on the bid list has enterd a bid or passed. Passing currently depends on MagicDKP Client - there's no passing mechanism in whisper bidding."],
	 width = "full", 
	 order = 70,
      },
      priorities = {
	 type = "input",
	 multiline = true,
	 name = L["Bid Priorities"],
	 desc = L["The list of bid priorities that are sent to the MagicDKP Client. Useful if you separate bids main spec and off spec bids for example. Has no effect on whisper bids."],
	 width = "full", 
      }
   }
}
