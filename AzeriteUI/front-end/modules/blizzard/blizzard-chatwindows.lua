local ADDON, Private = ...
local Core = Wheel("LibModule"):GetModule(ADDON)
if (not Core) then 
	return 
end

local Module = Core:NewModule("BlizzardChatFrames", "LibMessage", "LibEvent", "LibDB", "LibFrame", "LibHook", "LibSecureHook", "LibChatWindow", "LibFader")

-- Lua API
local _G = _G
local ipairs = ipairs
local math_floor = math.floor
local string_format = string.format
local string_gsub = string.gsub
local string_match = string.match
local string_len = string.len
local string_sub = string.sub
local table_insert = table.insert

-- WoW API
local FCF_GetButtonSide = FCF_GetButtonSide
local FCF_SetWindowAlpha = FCF_SetWindowAlpha
local FCF_SetWindowColor = FCF_SetWindowColor
local FCF_Tab_OnClick = FCF_Tab_OnClick
local FCF_UpdateButtonSide = FCF_UpdateButtonSide
local GetGuildRosterMOTD = GetGuildRosterMOTD
local IsInInstance = IsInInstance
local IsShiftKeyDown = IsShiftKeyDown
local UIFrameFadeRemoveFrame = UIFrameFadeRemoveFrame
local UIFrameIsFading = UIFrameIsFading
local UnitAffectingCombat = UnitAffectingCombat
local VoiceChat_IsLoggedIn = C_VoiceChat and C_VoiceChat.IsLoggedIn

-- Private API
local Colors = Private.Colors
local GetConfig = Private.GetConfig
local GetLayout = Private.GetLayout
local IsClassic = Private.IsClassic
local IsTBC = Private.IsTBC
local IsRetail = Private.IsRetail

local alphaLocks = {}
local frameCache = {}

-- Pure methods
local Blizz_ChatFrame = CreateFrame("ScrollingMessageFrame")
local Blizz_ChatFrame_MT = { __index = Blizz_ChatFrame }
local Blizz_AddMessage = Blizz_ChatFrame_MT.__index.AddMessage

-- Script Handlers
-------------------------------------------------------
local HZ = 1/60
local OnUpdate = function(frame, elapsed)
	if (frame.clearSpam) or (frame.clearSpamDisableDelay) then
		--ChatFrame1:Clear()
		if (frame.clearSpamDisableDelay) then
			frame.clearSpamDisableDelay = frame.clearSpamDisableDelay - elapsed
			if (frame.clearSpamDisableDelay < 0) then
				frame.clearSpam = nil
				frame.clearSpamDisableDelay = nil
				frame.showGMotDDelay = 10 -- seems to require this long to be available.
			end
		end
	end

	if (frame.showGMotDDelay) then
		frame.showGMotDDelay = frame.showGMotDDelay - elapsed
		if (frame.showGMotDDelay < 0) then 
			frame.showGMotDDelay = nil
			local gmotd = GetGuildRosterMOTD()
			if (gmotd) and (gmotd ~= "") then 
				local info = ChatTypeInfo["GUILD"]
				local string = string_format(GUILD_MOTD_TEMPLATE, gmotd)
				ChatFrame1:AddMessage(string, info.r, info.g, info.b, info.id)
			end
		end 
	end

	-- Throttle these updates
	frame.elapsed = frame.elapsed + elapsed
	if (frame.elapsed < HZ) then
		return
	end

	local self = frame.module
	local isMouseOver, fadeIn, fadeOut

	-- Set the flag if the frame is currently mouseovered.
	if (frame:IsMouseOver(40,-60,-70,20)) then
		isMouseOver = true
		if (isMouseOver ~= self.isMouseOver) then
			self.isMouseOver = true
			self:UpdateChatDockPosition()
		elseif (frame.scheduledDockUpdate) then
			frame.scheduledDockUpdate = GetTime() + 1.5
		end
	else
		if (frame.scheduledDockUpdate) then
			if (GetTime() > frame.scheduledDockUpdate) then
				frame.scheduledDockUpdate = nil
				self.isMouseOver = nil
				self:UpdateChatDockPosition()
			end
		elseif (self.isMouseOver) then
			frame.scheduledDockUpdate = GetTime() + 1.5
		end
	end

	-- Pretend the selected chatframe is mouseovered
	-- if it's not currently at the bottom/current chat.
	-- This is to force the buttons visible easily.
	if (not isMouseOver) then
		local chatFrame = self:GetSelectedChatFrame()
		if (chatFrame) and (not chatFrame:AtBottom()) then 
			isMouseOver = true
		end
	end

	-- When frame is mouseovered,
	-- but the flag isn't set.
	if (isMouseOver) then
		if (not frame.isMouseOver) then
			frame.isMouseOver = true
		end
		-- set flag to initiate fade-in
		fadeIn = true
	else
		-- When the mouseover flag is set,
		-- but no actual hovering occurring.
		if (frame.isMouseOver) then
			frame.isMouseOver = nil
		end
		-- set flag to initiate fade-out
		-- *don't do this if editbox is open
		fadeOut = true
	end
	if (fadeIn) then
		self:UpdateMainWindowButtonDisplay(true)
		self:UpdateChatWindowAlpha(ChatFrame1)

	elseif (fadeOut) then
		self:UpdateMainWindowButtonDisplay()
		self:UpdateChatWindowAlpha(ChatFrame1)
	end
	frame.elapsed = 0
end

-- Updates
-------------------------------------------------------
Module.UpdateChatWindowAlpha = function(self, frame)
	local alpha
	if self:GetChatWindowCurrentEditBox(frame):IsShown() then
		alpha = 0.5
	else
		alpha = 0.8
	end
	for index, value in pairs(CHAT_FRAME_TEXTURES) do
		if (not value:find("Tab")) then
			local object = _G[frame:GetName()..value]
			if object:IsShown() then
				UIFrameFadeRemoveFrame(object)
				object:SetAlpha(alpha)
			end
		end
	end
end 

Module.UpdateChatWindowButtons = function(self, frame)

	if (IsClassic or IsTBC) then
		return
	end

	local buttonSide = FCF_GetButtonSide(frame)

	local buttonFrame = self:GetChatWindowButtonFrame(frame)
	local minimizeButton = self:GetChatWindowMinimizeButton(frame)
	local channelButton = self:GetChatWindowChannelButton()
	local deafenButton = self:GetChatWindowVoiceDeafenButton()
	local muteButton =self:GetChatWindowVoiceMuteButton()
	local menuButton = self:GetChatWindowMenuButton()
	local scrollBar = self:GetChatWindowScrollBar(frame)
	local scrollToBottomButton = self:GetChatWindowScrollToBottomButton(frame)

	local frameHeight = frame:GetHeight()
	local buttonCount, spaceNeeded = 0, 0
	local anchorTop, anchorBottom

	-- Calculate available space based on visible buttons
	if frame.isDocked then 
		if (channelButton and channelButton:IsShown()) then 
			buttonCount = buttonCount + 1
			spaceNeeded = spaceNeeded + channelButton:GetHeight()
			anchorTop = channelButton
		end 
		if (deafenButton and deafenButton:IsShown()) then 
			buttonCount = buttonCount + 1
			spaceNeeded = spaceNeeded + deafenButton:GetHeight()
			anchorTop = deafenButton
		end 
		if (muteButton and muteButton:IsShown()) then 
			buttonCount = buttonCount + 1
			spaceNeeded = spaceNeeded + muteButton:GetHeight()
			anchorTop = muteButton
		end 
		if (menuButton and menuButton:IsShown()) then 
			buttonCount = buttonCount + 1
			spaceNeeded = spaceNeeded + menuButton:GetHeight()
			anchorBottom = menuButton
		end 
	else
		if (minimizeButton and minimizeButton:IsShown()) then 
			buttonCount = buttonCount + 1
			spaceNeeded = spaceNeeded + minimizeButton:GetHeight()
			anchorTop = minimizeButton
		end 
	end 

	-- Isn't the bar always here...?
	if scrollBar then

		-- Cram it in with the other buttons when there is room enough
		if (frameHeight >= spaceNeeded) then 
			scrollBar:ClearAllPoints()
			if anchorTop then 
				scrollBar:SetPoint("TOP", anchorTop, "BOTTOM", 0, -4)
			else 
				scrollBar:SetPoint("TOP", buttonFrame, "TOP", 0, -4)
			end 
			if (scrollToBottomButton and scrollToBottomButton:IsShown()) then
				scrollToBottomButton:ClearAllPoints()
				if anchorBottom then 
					scrollToBottomButton:SetPoint("BOTTOM", anchorBottom, "TOP", 0, 9)
				else 
					scrollToBottomButton:SetPoint("BOTTOM", buttonFrame, "BOTTOM", 0, 4)
				end 
				scrollBar:SetPoint("BOTTOM", scrollToBottomButton, "TOP", 0, 5)
			else
				if anchorBottom then 
					scrollBar:SetPoint("BOTTOM", anchorBottom, "TOP", 0, 9)
				else 
					scrollBar:SetPoint("BOTTOM", buttonFrame, "BOTTOM", 0, 4)
				end 
			end 
		else 

			-- Put it back on the opposite side when there's not enough room
			if (buttonSide == "left") then 
				scrollBar:ClearAllPoints()
				scrollBar:SetPoint("TOPLEFT", frame, "TOPRIGHT", -13, -4)
				if (scrollToBottomButton and scrollToBottomButton:IsShown()) then
					scrollToBottomButton:SetPoint("BOTTOMRIGHT", frame.ResizeButton, "TOPRIGHT", -9, -11)
					scrollBar:SetPoint("BOTTOM", scrollToBottomButton, "TOP", -13, 5)
				elseif (frame.ResizeButton and frame.ResizeButton:IsShown()) then
					scrollBar:SetPoint("BOTTOM", frame.ResizeButton, "TOP", -13, 5)
				else
					scrollBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", -13, 5)
				end

			elseif (buttonSide == "right") then 
				scrollBar:ClearAllPoints()
				scrollBar:SetPoint("TOPRIGHT", frame, "TOPLEFT", 13, -4)
				if (scrollToBottomButton and scrollToBottomButton:IsShown()) then
					scrollToBottomButton:SetPoint("BOTTOMLEFT", frame.ResizeButton, "TOPLEFT", 9, -11)
					scrollBar:SetPoint("BOTTOM", scrollToBottomButton, "TOP", 13, 5)
				elseif (frame.ResizeButton and frame.ResizeButton:IsShown()) then
					scrollBar:SetPoint("BOTTOM", frame.ResizeButton, "TOP", 13, 5)
				else
					scrollBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", 13, 5)
				end
			end 
		end 
	end

end

Module.UpdateMainWindowButtonDisplay = function(self, forced)

	local show = forced
	local frame = self:GetSelectedChatFrame()
	local channelButton = self:GetChatWindowChannelButton()
	local deafenButton = self:GetChatWindowVoiceDeafenButton()
	local muteButton =self:GetChatWindowVoiceMuteButton()
	local menuButton = self:GetChatWindowMenuButton()

	if (not show) and (frame and frame.isDocked) then
		local editBox = self:GetChatWindowEditBox(frame)
		if (editBox and editBox:IsShown()) then
			show = true
		end
	end

	if (not show) and (frame and not frame:AtBottom()) then
		show = true
	end

	if show then 

		local buttonFrame = self:GetChatWindowButtonFrame(frame)
		if buttonFrame then
			buttonFrame:Show()
			buttonFrame:SetAlpha(1)
		end

		if channelButton then 
			channelButton:Show()
		end 

		if VoiceChat_IsLoggedIn() then 
			if deafenButton then 
				deafenButton:Show()
			end 
			if muteButton then 
				muteButton:Show()
			end 
		else 
			if deafenButton then 
				deafenButton:Hide()
			end 
			if muteButton then 
				muteButton:Hide()
			end 
		end 

		if menuButton then 
			menuButton:Show()
		end

	else
		
		local buttonFrame = self:GetChatWindowButtonFrame(frame)
		if buttonFrame then
			buttonFrame:Hide()
		end

		if channelButton then 
			channelButton:Hide()
		end 
		
		if deafenButton then 
			deafenButton:Hide()
		end 

		if muteButton then 
			muteButton:Hide()
		end 

		if menuButton then 
			menuButton:Hide()
		end 
	end 

	-- Post update button alignment in case changes to visible ones
	if frame then 
		self:UpdateChatWindowButtons(frame)
	end 
end

Module.UpdateChatWindowScale = function(self, frame)
	local targetScale = self:GetFrame("UICenter"):GetEffectiveScale()
	local parentScale = frame:GetParent():GetScale()
	local scale = targetScale / parentScale

	frame:SetScale(scale)

	-- Chat tabs are direct descendants of the general dock manager, 
	-- which in turn is a direct descendant of UIParent
	local windowTab = self:GetChatWindowTab(frame)
	if windowTab then 
		windowTab:SetScale(scale)
	end 

	-- The editbox is a child of the chat frame
	local editBox = self:GetChatWindowEditBox(frame)
	if editBox then 
		editBox:SetScale(scale)
	end 
end

Module.UpdateChatWindowScales = function(self)

	local targetScale = self:GetFrame("UICenter"):GetEffectiveScale()
	local parentScale = UIParent:GetScale()
	local scale = targetScale / parentScale

	local channelButton = self:GetChatWindowChannelButton()
	if channelButton then 
		channelButton:SetScale(scale)
	end 

	local deafenButton = self:GetChatWindowVoiceDeafenButton()
	if deafenButton then 
		deafenButton:SetScale(scale)
	end 

	local muteButton =self:GetChatWindowVoiceMuteButton()
	if muteButton then 
		muteButton:SetScale(scale)
	end 

	local menuButton = self:GetChatWindowMenuButton()
	if menuButton then 
		menuButton:SetScale(scale)
	end 

	for _,frameName in self:GetAllChatWindows() do 
		local frame = _G[frameName]
		if frame then 
			self:UpdateChatWindowScale(frame)
		end 
	end 
end 

Module.UpdateChatOutlines = function(self)
	for frame in pairs(frameCache) do
		frame:SetFontObject(frame:GetFontObject())
	end
end

Module.UpdateBNToastFramePosition = function(self)
	if (self.lockBNFrame) then 
		return 
	end
	self.lockBNFrame = true 

	-- Retrieve frames and sizes
	local anchorFrame = self.BNAnchorFrame
	local toastFrame = _G.BNToastFrame
	local width, height = _G.UIParent:GetSize()
	local left = anchorFrame:GetLeft()
	local right = width - anchorFrame:GetRight()
	local bottom = anchorFrame:GetBottom() 
	local top = height - anchorFrame:GetTop()

	-- Figure out the anchors 
	local point = ((bottom < top) and "BOTTOM" or "TOP") .. ((left < right) and "LEFT" or "RIGHT") 
	local rPoint = ((bottom < top) and "TOP" or "BOTTOM") .. ((left < right) and "LEFT" or "RIGHT") 
	local offsetY = (bottom < top) and 16 or -(16 + 30) -- TODO: adjust for super large edit boxes

	-- Position the toast frame
	toastFrame:ClearAllPoints()
	toastFrame:SetPoint(point, anchorFrame, rPoint, 0, offsetY)

	self.lockBNFrame = nil
end

Module.UpdateChatDockPosition = function(self)
	local layout = self.layout
	local frame = self.frame 
	-- Not the most elegant solution, but it prevents explorer mode movement if the theme doesn't support it, 
	-- without affecting any of the currently registered events or callbacks. Easiest way right now.
	if (frame) and (layout.DefaultChatFramePlaceFaded) and (layout.DefaultClampRectInsetsFaded) then 
		frame:ClearAllPoints()
		local coreDB = GetConfig(ADDON)
		if (coreDB and coreDB.enableHealerMode) then 
			ChatFrame1:SetClampRectInsets(unpack(layout.AlternateClampRectInsets))
			frame:SetPoint(unpack(layout.AlternateChatFramePlace))
		else 
			local db = GetConfig("ExplorerMode")
			if (db.enableExplorer and db.enableExplorerChat) and (self:GetCurrentFaderState() == "safe") and (not self.isMouseOver) then
				ChatFrame1:SetClampRectInsets(unpack(layout.DefaultClampRectInsetsFaded))
				frame:SetPoint(unpack(layout.DefaultChatFramePlaceFaded))
			else
				ChatFrame1:SetClampRectInsets(unpack(layout.DefaultClampRectInsets))
				frame:SetPoint(unpack(layout.DefaultChatFramePlace))
			end
		end
	end
end

-- Callbacks used by the back-end
-------------------------------------------------------
-- *Supposed to NOT be called for auto-disabled modules,
--  but it sometimes happen anyway. 
-- *Now checking for layout data before executing,
--  as as temporary simple workaround until properly fixed.
-------------------------------------------------------
Module.PostCreateTemporaryChatWindow = function(self, frame, ...)
	local layout = self.layout
	if (not self.layout) then
		return
	end

	local chatType, chatTarget, sourceChatFrame, selectWindow = ...

	-- Some temporary frames have weird fonts (like the pet battle log)
	frame:SetFontObject(ChatFrame1:GetFontObject())

	-- Run the normal post creation method
	self:PostCreateChatWindow(frame)
end 

Module.PostCreateChatWindow = function(self, frame)
	local layout = self.layout
	if (not self.layout) then
		return
	end

	frameCache[frame] = true

	-- Window
	------------------------------
	frame:SetFading(layout.ChatFadeTime)
	frame:SetTimeVisible(layout.ChatVisibleTime)
	frame:SetIndentedWordWrap(layout.ChatIndentedWordWrap) 

	-- just lock all frames away from our important objects
	frame:SetClampRectInsets(unpack(layout.DefaultClampRectInsets))

	-- Set the frame's backdrop alpha and color
	FCF_SetWindowColor(frame, 0, 0, 0, 0)
	FCF_SetWindowAlpha(frame, 0, 1)

	-- Update the scale of this window
	self:UpdateChatWindowScale(frame)

	-- Font
	------------------------------
	local locked
	local updateFont = function(frame)
		if (locked) then
			return
		end
		locked = true
		local fontObject = frame:GetFontObject()
		local font, size, style = fontObject:GetFont()
		if (self.db.enableChatOutline) then
			fontObject:SetFont(font, size, "OUTLINE")
			fontObject:SetShadowColor(0,0,0,.5)
		else
			fontObject:SetFont(font, size, "")
			fontObject:SetShadowColor(0,0,0,.75)
		end
		fontObject:SetShadowOffset(-.75, -.75)
		locked = false
	end

	hooksecurefunc(frame, "SetFontObject", updateFont)
	hooksecurefunc(frame, "SetFont", updateFont)

	-- Trigger an initial update
	frame:SetFontObject(frame:GetFontObject())

	-- Tabs
	------------------------------
	-- strip away textures
	for tex in self:GetChatWindowTabTextures(frame) do 
		tex:SetTexture(nil)
		tex:SetAlpha(0)
	end 

	-- Take control of the tab's alpha changes
	-- and disable blizzard's own fading. 
	local tab = self:GetChatWindowTab(frame)
	tab:SetAlpha(1)
	tab.SetAlpha = UIFrameFadeRemoveFrame

	local tabText = self:GetChatWindowTabText(frame) 
	tabText:Hide()

	local tabIcon = self:GetChatWindowTabIcon(frame)
	if tabIcon then 
		tabIcon:Hide()
	end

	-- Hook all tab sizes to slightly smaller than ChatFrame1's chat
	hooksecurefunc(tabText, "Show", function() 
		-- Make it 2px smaller (before scaling), 
		-- but make 10px the minimum size.
		local font, size, style = ChatFrame1:GetFontObject():GetFont()
		size = math_floor(((size*10) + .5)/10)
		if (size + 2 >= 10) then 
			size = size - 2
		end 

		-- Stupid blizzard changing sizes by 0.0000001 and similar
		local ourFont, ourSize, ourStyle = tabText:GetFont()
		ourSize = math_floor(((ourSize*10) + .5)/10)

		-- Make sure the tabs keeps the same font as the frame, 
		-- and not some completely different size as it does by default. 
		if (ourFont ~= font) or (ourSize ~= size) or (style ~= ourStyle) then 
			tabText:SetFont(font, size, style)
		end 
	end)

	-- Toggle tab text visibility on hover
	tab:HookScript("OnEnter", function() 
		frame.isMouseOverTab = true
		tabText:Show()
		if tabIcon and frame.isTemporary then 
			tabIcon:Show()
		end
	end)
	tab:HookScript("OnLeave", function() 
		frame.isMouseOverTab = false
		tabText:Hide() 
		if tabIcon and frame.isTemporary then 
			tabIcon:Hide()
		end
	end)
	tab:HookScript("OnClick", function() 
		frame.isMouseOverTab = false
		-- We need to hide both tabs and button frames here, 
		-- but it must depend on visible editBoxes. 
		local frame = self:GetSelectedChatFrame()
		local editBox = self:GetChatWindowCurrentEditBox(frame)
		if editBox then
			editBox:Hide() 
		end
		local buttonFrame = self:GetChatWindowButtonFrame(frame)
		if buttonFrame then
			buttonFrame:Hide() 
		end
	end)

	local anywhereButton = self:GetChatWindowClickAnywhereButton(frame)
	if anywhereButton then 
		anywhereButton:HookScript("OnEnter", function() tabText:Show() end)
		anywhereButton:HookScript("OnLeave", function() tabText:Hide() end)
		anywhereButton:HookScript("OnClick", function() 
			if frame then 
				FCF_Tab_OnClick(frame) -- click the tab to actually select this frame
				local editBox = self:GetChatWindowCurrentEditBox(frame)
				if editBox then
					editBox:Hide() -- hide the annoying half-transparent editBox 
				end
			end 
		end)
	end

	-- EditBox
	------------------------------
	-- strip away textures
	for tex in self:GetChatWindowEditBoxTextures(frame) do 
		tex:SetTexture(nil)
		tex:SetAlpha(0)
	end 

	local editBox = self:GetChatWindowEditBox(frame)
	editBox:Hide()
	editBox:SetAltArrowKeyMode(false) 
	editBox:SetHeight(layout.EditBoxHeight)
	editBox:ClearAllPoints()
	editBox:SetPoint("LEFT", frame, "LEFT", -layout.EditBoxOffsetH, 0)
	editBox:SetPoint("RIGHT", frame, "RIGHT", layout.EditBoxOffsetH, 0)
	editBox:SetPoint("TOP", frame, "BOTTOM", 0, -1)

	-- do any editBox backdrop styling here

	-- make it auto-hide when focus is lost
	editBox:HookScript("OnEditFocusGained", function(self) self:Show() end)
	editBox:HookScript("OnEditFocusLost", function(self) self:Hide() end)

	-- hook editBox updates to our coloring method
	--hooksecurefunc("ChatEdit_UpdateHeader", function(...) self:UpdateEditBox(...) end)

	-- Avoid dying from having the editBox open in combat
	editBox:HookScript("OnTextChanged", function(self)
		local msg = self:GetText()
		local maxRepeats = UnitAffectingCombat("player") and 5 or 10
		if (string_len(msg) > maxRepeats) then
			local stuck = true
			for i = 1, maxRepeats, 1 do 
				if (string_sub(msg,0-i, 0-i) ~= string_sub(msg,(-1-i),(-1-i))) then
					stuck = false
					break
				end
			end
			if stuck then
				self:SetText("")
				self:Hide()
				return
			end
		end
	end)

	-- ButtonFrame
	------------------------------
	local buttonFrame = self:GetChatWindowButtonFrame(frame)
	buttonFrame:SetWidth(layout.ButtonFrameWidth)

	for tex in self:GetChatWindowButtonFrameTextures(frame) do 
		tex:SetTexture(nil)
		tex:SetAlpha(0)
	end

	editBox:HookScript("OnShow", function() 
		local frame = self:GetSelectedChatFrame()
		if (frame) then
			if (IsRetail) then
				local buttonFrame = self:GetChatWindowButtonFrame(frame)
				if (buttonFrame) then
					buttonFrame:Show()
					buttonFrame:SetAlpha(1)
				end
				if frame.isDocked then
					self:UpdateMainWindowButtonDisplay(true)
				end
				self:UpdateChatWindowButtons(frame)
			else
				self:UpdateMainWindowButtonDisplay()
			end
			self:UpdateChatWindowAlpha(frame)

			-- Hook all editbox chat sizes to the same as ChatFrame1
			local fontObject = frame:GetFontObject()
			local font, size, style = fontObject:GetFont()
			local x,y = fontObject:GetShadowOffset()
			local r, g, b, a = fontObject:GetShadowColor()
			local ourFont, ourSize, ourStyle = editBox:GetFont()

			-- Stupid blizzard changing sizes by 0.0000001 and similar
			size = math_floor(((size*10) + .5)/10)
			ourSize = math_floor(((ourSize*10) + .5)/10)

			editBox:SetFontObject(fontObject)
			editBox.header:SetFontObject(fontObject)

			-- Make sure the editbox keeps the same font as the frame, 
			-- and not some completely different size as it does by default. 
			if (ourFont ~= font) or (ourSize ~= size) or (style ~= ourStyle) then 
				editBox:SetFont(font, size, style)
			end 

			local ourFont, ourSize, ourStyle = editBox.header:GetFont()
			ourSize = math_floor(((ourSize*10) + .5)/10)

			if (ourFont ~= font) or (ourSize ~= size) or (style ~= ourStyle) then 
				editBox.header:SetFont(font, size, style)
			end 

			editBox:SetShadowOffset(x,y)
			editBox:SetShadowColor(r,g,b,a)

			editBox.header:SetShadowOffset(x,y)
			editBox.header:SetShadowColor(r,g,b,a)
		end
	end)

	editBox:HookScript("OnHide", function() 
		local frame = self:GetSelectedChatFrame()
		if (frame) then
			if (IsRetail) then
				local buttonFrame = self:GetChatWindowButtonFrame(frame)
				if buttonFrame then
					buttonFrame:Hide()
				end
				if frame.isDocked then
					self:UpdateMainWindowButtonDisplay(false)
				end
				self:UpdateChatWindowButtons(frame)
			else
				self:UpdateMainWindowButtonDisplay()
			end
			self:UpdateChatWindowAlpha(frame)
		end
	end)

	hooksecurefunc(buttonFrame, "SetAlpha", function(buttonFrame, alpha)
		if alphaLocks[buttonFrame] then 
			return 
		else
			alphaLocks[buttonFrame] = true
			local frame = self:GetSelectedChatFrame()
			if UIFrameIsFading(frame) then
				UIFrameFadeRemoveFrame(frame)
			end	
			local editBox = self:GetChatWindowCurrentEditBox(frame)
			if editBox then 
				if editBox:IsShown() then
			--		buttonFrame:SetAlpha(1) 
				else
			--		buttonFrame:SetAlpha(0)
				end 
			end 
			alphaLocks[buttonFrame] = false
		end 
	end)
	buttonFrame:Hide()

	-- Frame specific buttons
	------------------------------
	local minimizeButton = self:GetChatWindowMinimizeButton(frame)
	if minimizeButton then 
		self:SetUpButton(minimizeButton, layout.ButtonTextureMinimizeButton)
	end 

	local scrollUpButton = self:GetChatWindowScrollUpButton(frame)
	if scrollUpButton then 
		self:SetUpButton(scrollUpButton, layout.ButtonTextureScrollUpButton)
	end 

	local scrollDownButton = self:GetChatWindowScrollDownButton(frame)
	if scrollDownButton then 
		self:SetUpButton(scrollDownButton, layout.ButtonTextureScrollDownButton)
	end 

	local scrollToBottomButton = self:GetChatWindowScrollToBottomButton(frame)
	if scrollToBottomButton then 
		self:SetUpButton(scrollToBottomButton, layout.ButtonTextureScrollToBottomButton)
	end 

end 

-- Setup
-------------------------------------------------------
Module.SetUpAlphaScripts = function(self)
	_G.CHAT_FRAME_BUTTON_FRAME_MIN_ALPHA = 0

	-- avoid mouseover alpha change, yet keep the background textures
	local alphaProxy = function(...) self:UpdateChatWindowAlpha(...) end
	
	hooksecurefunc("FCF_FadeInChatFrame", alphaProxy)
	hooksecurefunc("FCF_FadeOutChatFrame", alphaProxy)
	hooksecurefunc("FCF_SetWindowAlpha", alphaProxy)
end 

Module.SetUpScrollScripts = function(self)

	-- allow SHIFT + MouseWheel to scroll to the top or bottom
	hooksecurefunc("FloatingChatFrame_OnMouseScroll", function(self, delta)
		if (delta < 0) then
			if IsShiftKeyDown() then
				self:ScrollToBottom()
			end
		elseif (delta > 0) then
			if IsShiftKeyDown() then
				self:ScrollToTop()
			end
		end
	end)

	if (IsRetail) then
		hooksecurefunc("FCF_UpdateButtonSide", function(frame) self:UpdateChatWindowButtons(frame) end)
		hooksecurefunc("FCF_UpdateScrollbarAnchors", function(frame) self:UpdateChatWindowButtons(frame) end)
	end
end 

Module.SetUPBNToastFrame = function(self)
	if self.BNAnchorFrame then 
		return 
	end 

	local anchorFrame = CreateFrame("Frame")
	anchorFrame:Hide()
	anchorFrame:SetAllPoints(self.frame)

	self:SetHook(BNToastFrame, "OnShow", "UpdateBNToastFramePosition")
	self:SetSecureHook(BNToastFrame, "SetPoint", "UpdateBNToastFramePosition")
	self:SetSecureHook(self.frame, "SetPoint", "UpdateBNToastFramePosition")

	self.BNAnchorFrame = anchorFrame
end

Module.SetUpMainFrames = function(self)
	local layout = self.layout

	-- Create a holder frame for our main chat window,
	-- which we'll use to move and size the window without 
	-- having to parent it to our upscaled master frame. 
	-- 
	-- The problem is that WoW renders chat to pixels 
	-- when the font is originally defined, 
	-- and any scaling later on is applied to that pixel font, 
	-- not to the original vector font. 
	local frame = self:CreateFrame("Frame", nil, "UICenter")
	frame:SetPoint(unpack(layout.DefaultChatFramePlace))
	frame:SetSize(unpack(layout.DefaultChatFrameSize))
	self.frame = frame

	self:HandleAllChatWindows()
	self:SetChatWindowAsSlaveTo(ChatFrame1, frame)

	frame.module = self
	frame.clearSpam = nil
	frame.clearSpamDisableDelay = nil
	frame.elapsed = 0
	frame.fading = nil
	frame.fadeDirection = nil
	frame.fadeDelay = 0
	frame.fadeDuration = 0
	frame.timeFading = 0
	frame:SetScript("OnUpdate", OnUpdate)

	FCF_SetWindowColor(ChatFrame1, 0, 0, 0, 0)
	FCF_SetWindowAlpha(ChatFrame1, 0, 1)
	FCF_UpdateButtonSide(ChatFrame1)
	FCF_SetLocked(ChatFrame1, true)

	hooksecurefunc("FCF_ToggleLockOnDockedFrame", function() 
		local chatFrame = FCF_GetCurrentChatFrame()
		for _, frame in pairs(FCFDock_GetChatFrames(GENERAL_CHAT_DOCK)) do
			FCF_SetLocked(frame, true)
		end
	end)
end 

Module.SetUpButton = function(self, button, texture)
	local layout = self.layout

	local normal = button:GetNormalTexture()
	normal:SetTexture(texture or layout.ButtonTextureNormal)
	normal:SetVertexColor(unpack(layout.ButtonTextureColor))
	normal:ClearAllPoints()
	normal:SetPoint("CENTER", 0, 0)
	normal:SetSize(unpack(layout.ButtonTextureSize))

	local highlight = button:GetHighlightTexture()
	highlight:SetTexture(texture or layout.ButtonTextureNormal)
	highlight:SetVertexColor(1,1,1,.075)
	highlight:ClearAllPoints()
	highlight:SetPoint("CENTER", 0, 0)
	highlight:SetSize(unpack(layout.ButtonTextureSize))
	highlight:SetBlendMode("ADD")

	local pushed = button:GetPushedTexture()
	pushed:SetTexture(texture or layout.ButtonTextureNormal)
	pushed:SetVertexColor(unpack(layout.ButtonTextureColor))
	pushed:ClearAllPoints()
	pushed:SetPoint("CENTER", -1, -2)
	pushed:SetSize(unpack(layout.ButtonTextureSize))

	local disabled = button:GetDisabledTexture()
	if disabled then 
		disabled:SetTexture(texture or layout.ButtonTextureNormal)
		disabled:SetVertexColor(unpack(layout.ButtonTextureColor))
		disabled:SetDesaturated(true)
		disabled:ClearAllPoints()
		disabled:SetPoint("CENTER", 0, 0)
		disabled:SetSize(unpack(layout.ButtonTextureSize))
	end 

	local flash = button.Flash
	if flash then 
		flash:SetTexture(texture or layout.ButtonTextureNormal)
		flash:SetVertexColor(1,1,1,.075)
		flash:ClearAllPoints()
		flash:SetPoint("CENTER", 0, 0)
		flash:SetSize(unpack(layout.ButtonTextureSize))
		flash:SetBlendMode("ADD")
	end 

	button:HookScript("OnMouseDown", function() 
		highlight:SetPoint("CENTER", -1, -2) 
		if flash then 
			flash:SetPoint("CENTER", -1, -2) 
		end 
	end)

	button:HookScript("OnMouseUp", function() 
		highlight:SetPoint("CENTER", 0, 0) 
		if flash then 
			flash:SetPoint("CENTER", 0, 0) 
		end 
	end)
end 

Module.SetUpMainButtons = function(self)
	local layout = self.layout
	local channelButton = self:GetChatWindowChannelButton()
	if channelButton then 
		self:SetUpButton(channelButton)
	end 
	local deafenButton = self:GetChatWindowVoiceDeafenButton()
	if deafenButton then 
		self:SetUpButton(deafenButton)
	end 
	local muteButton = self:GetChatWindowVoiceMuteButton()
	if muteButton then 
		self:SetUpButton(muteButton)
	end 
	local menuButton = self:GetChatWindowMenuButton()
	if menuButton then 
		self:SetUpButton(menuButton, layout.ButtonTextureChatEmotes)
	end 
end 

-- Startup & Init
-------------------------------------------------------
Module.OnModeToggle = function(self, modeName)
	if (modeName == "healerMode") then 
		self:UpdateChatDockPosition()
	end
end

Module.OnEvent = function(self, event, ...)
	if (event == "PLAYER_ENTERING_WORLD") then
		-- Initiate chat clearing on login and manual reloads,
		-- but not when zoning in or out of instances.
		local isInitialLogin, isReloadingUi = ...
		if (isInitialLogin) or (isReloadingUi) then
			self.frame.clearSpam = true
			self.frame.clearSpamDisableDelay = 1.5
			self.frame.showGMotDDelay = nil
		end
		self:UpdateChatDockPosition()

	elseif (event == "GP_FADER_STATE_ACHIEVED") then
		local state = ...
		if (state == "safe") then
			local now = GetTime()
			if (self.frame.scheduledDockUpdate) then
				if (self.frame.scheduledDockUpdate < now + .1) then
					self.frame.scheduledDockUpdate = now + .1
				end
			else
				self.frame.scheduledDockUpdate = now + .1
			end
		else
			self:UpdateChatDockPosition()
		end
		return

	elseif (event == "GP_EXPLORER_MODE_DISABLED") or (event == "GP_EXPLORER_MODE_ENABLED")
		or (event == "GP_EXPLORER_CHAT_ENABLED") or (event == "GP_EXPLORER_CHAT_DISABLED")
		or (event == "GP_FADER_STATE_LOST")
	then
		self:UpdateChatDockPosition()
		return
	end

	self:UpdateMainWindowButtonDisplay()

	-- Do this cause taint? Shouldn't, but you never know. 
	if ((event == "GP_INTERFACE_SCALE_UPDATE") or (event == "GP_WORLD_SCALE_UPDATE")) then 
		self:UpdateChatWindowScales()
	end 
end 

Module.OnInit = function(self)
	self.db = GetConfig(self:GetName())
	self.layout = GetLayout(self:GetName())
	if (not self.layout) then
		return self:SetUserDisabled(true)
	end

	local OptionsMenu = Core:GetModule("OptionsMenu", true)
	if (OptionsMenu) then
		local callbackFrame = OptionsMenu:CreateCallbackFrame(self)
		callbackFrame:AssignProxyMethods("UpdateChatOutlines")
		callbackFrame:AssignSettings(self.db)
		callbackFrame:AssignCallback([=[
			if name then 
				name = string.lower(name); 
			end 
			if (name == "change-enablechatoutline") then 
				self:SetAttribute("enableChatOutline", value); 
				self:CallMethod("UpdateChatOutlines"); 
			end 
		]=])
	end
	
	self:SetUpAlphaScripts()
	self:SetUpScrollScripts()
	self:SetUpMainFrames()
	self:SetUpMainButtons()
	self:SetUPBNToastFrame()
	self:UpdateChatWindowScales()
	self:UpdateChatDockPosition()
	self:UpdateChatOutlines()
end 

Module.OnEnable = function(self)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnEvent")
	self:RegisterEvent("GUILD_MOTD", "OnEvent")
	self:RegisterEvent("VOICE_CHAT_LOGIN", "OnEvent")
	self:RegisterEvent("VOICE_CHAT_LOGOUT", "OnEvent")
	self:RegisterEvent("VOICE_CHAT_MUTED_CHANGED", "OnEvent")
	self:RegisterEvent("VOICE_CHAT_SILENCED_CHANGED", "OnEvent")
	self:RegisterEvent("VOICE_CHAT_DEAFENED_CHANGED", "OnEvent")
	self:RegisterEvent("VOICE_CHAT_CHANNEL_MEMBER_MUTE_FOR_ME_CHANGED", "OnEvent")
	self:RegisterEvent("VOICE_CHAT_CHANNEL_MEMBER_MUTE_FOR_ALL_CHANGED", "OnEvent")
	self:RegisterEvent("VOICE_CHAT_CHANNEL_MEMBER_SILENCED_CHANGED", "OnEvent")

	if (self.layout) and (self.layout.DefaultChatFramePlaceFaded) and (self.layout.DefaultClampRectInsetsFaded) then
		self:RegisterMessage("GP_EXPLORER_CHAT_ENABLED", "OnEvent")
		self:RegisterMessage("GP_EXPLORER_CHAT_DISABLED", "OnEvent")
		self:RegisterMessage("GP_EXPLORER_MODE_ENABLED", "OnEvent")
		self:RegisterMessage("GP_EXPLORER_MODE_DISABLED", "OnEvent")
		self:RegisterMessage("GP_FADER_STATE_ACHIEVED", "OnEvent")
		self:RegisterMessage("GP_FADER_STATE_LOST", "OnEvent")
	end
	
	self:RegisterMessage("GP_INTERFACE_SCALE_UPDATE", "OnEvent")
	self:RegisterMessage("GP_WORLD_SCALE_UPDATE", "OnEvent")
end 
