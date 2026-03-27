local Device = require("device")
local Screen = Device.screen
local TitleBar = require("ui/widget/titlebar")
local FocusManager = require("ui/widget/focusmanager")
local RadioButtonTable = require("ui/widget/radiobuttontable")
local ButtonTable = require("ui/widget/buttontable")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local Size = require("ui/size")
local FrameContainer = require("ui/widget/container/framecontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Geom = require("ui/geometry")
local MovableContainer = require("ui/widget/container/movablecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local _ = require("gettext")
local Blitbuffer = require("ffi/blitbuffer")


local ProviderSelectionDialog = FocusManager:extend{
    width = nil,
    providers = nil,
}

function ProviderSelectionDialog:init()
    self.width = self.width or math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * 0.8)
    local title_bar = TitleBar:new{
        width = self.width,
        with_bottom_line = true,
        title = _("Select Provider"),
        show_parent = self,
        info_text = _("Add addtional providers to config.lua to select them here")
    }

    local current_provider = G_reader_settings:readSetting("slopquiz_provider");
    local radio_buttons = {}
    table.insert(radio_buttons, {
        {
            text = _("Default - configure in menu"),
            checked = current_provider == nil or current_provider == "_default",
            provider = "_default",
        }
    })
    local invalid_provider_found = false
    if self.providers ~= nil then
        for i = 1, #self.providers do
            -- validate provider config
            local provider_is_valid = true
            if self.providers[i].name == nil or self.providers[i].name == "" then
                provider_is_valid = false
            end
            if self.providers[i].model == nil or self.providers[i].model == "" then
                provider_is_valid = false
            end
            if self.providers[i].api_key == nil then
                provider_is_valid = false
            end 

            if provider_is_valid then
                table.insert(radio_buttons, {
                    {
                        text = self.providers[i].name,
                        checked = current_provider == self.providers[i].name,
                        provider = self.providers[i],
                    }
                })
            else
                invalid_provider_found = true
            end
        end
        if invalid_provider_found then 
            UIManager:show(InfoMessage:new{
                text = _("Invalid provider found in config.lua. Ensure name, model, and api_key are provided for each provider")
            })
        end
    end

    self.radio_table = RadioButtonTable:new{
        radio_buttons = radio_buttons,
        width = self.width - 2 * Size.padding.large,
        parent = self,
    }

    self.button_table = ButtonTable:new{
        width = self.width - 2 * Size.padding.default,
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(self)
                    end,
                },
                {
                    text = _("Select"),
                    callback = function()
                        G_reader_settings:saveSetting("slopquiz_provider", self.radio_table.checked_button.provider.name)
                        UIManager:close(self)
                    end,
                }
            }
        },
        show_parent = self,
    }

    self.dialog_frame = FrameContainer:new{
        radius = Size.radius.window,
        bordersize = Size.border.window,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "center",
            title_bar,
            VerticalSpan:new{ width = Size.span.vertical_large },
            self.radio_table,
            VerticalSpan:new{ width = Size.span.vertical_large },
            self.button_table,
        }
    }

    self.movable = MovableContainer:new{
        self.dialog_frame,
    }
    self[1] = CenterContainer:new{
        dimen = Geom:new{
            w = Screen:getWidth(),
            h = Screen:getHeight(),
        },
        self.movable,
    }
end

function ProviderSelectionDialog:onShow()
    UIManager:setDirty(self, function()
        return "ui", self.dialog_frame.dimen
    end)
end

function ProviderSelectionDialog:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "ui", self.movable.dimen
    end)
end

return ProviderSelectionDialog