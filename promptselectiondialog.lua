local RadioButtonTable = require("ui/widget/radiobuttontable")
local ButtonTable = require("ui/widget/buttontable")
local TitleBar = require("ui/widget/titlebar")
local FrameContainer = require("ui/widget/container/framecontainer")
local FocusManager = require("ui/widget/focusmanager")
local MovableContainer = require("ui/widget/container/movablecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Device = require("device")
local Screen = Device.screen
local Size = require("ui/size")
local Geom = require("ui/geometry")
local Blitbuffer = require("ffi/blitbuffer")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local QuizPrompts = require("quizprompts")


local PromptSelectionDialog = FocusManager:extend{
    width = nil,
    user_prompts = nil, -- from config.lua
}

function PromptSelectionDialog:init()
    self.width = self.width or math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * 0.8)
    local title_bar = TitleBar:new{
        width = self.width,
        with_bottom_line = true,
        title = _("Select Quiz Prompt"),
        show_parent = self,
        info_text = _("Add custom prompts via user_prompts in config.lua"),
    }

    local current_prompt_id = G_reader_settings:readSetting("slopquiz_prompt_id") or "_default"
    local radio_buttons = {}

    -- built-in prompts
    for _, p in ipairs(QuizPrompts.BUILTIN_PROMPTS) do
        table.insert(radio_buttons, {{
            text = p.name,
            checked = current_prompt_id == p.id,
            provider = { id = p.id },
        }})
    end

    -- user-defined prompts from config.lua
    if self.user_prompts then
        for i, up in ipairs(self.user_prompts) do
            if type(up.name) == "string" and type(up.prompt) == "string" then
                local uid = "_user_" .. i
                table.insert(radio_buttons, {{
                    text = up.name,
                    checked = current_prompt_id == uid,
                    provider = { id = uid },
                }})
            end
        end
    end

    self.radio_table = RadioButtonTable:new{
        radio_buttons = radio_buttons,
        width = self.width - 2 * Size.padding.large,
        parent = self,
    }

    self.button_table = ButtonTable:new{
        width = self.width - 2 * Size.padding.default,
        buttons = {{
            {
                text = _("Cancel"),
                callback = function() UIManager:close(self) end,
            },
            {
                text = _("Select"),
                callback = function()
                    local pid = self.radio_table.checked_button.provider.id
                    G_reader_settings:saveSetting("slopquiz_prompt_id", pid)
                    UIManager:close(self)
                end,
            },
        }},
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

    self.movable = MovableContainer:new{ self.dialog_frame }
    self[1] = CenterContainer:new{
        dimen = Geom:new{ w = Screen:getWidth(), h = Screen:getHeight() },
        self.movable,
    }
end

function PromptSelectionDialog:onShow()
    UIManager:setDirty(self, function()
        return "ui", self.dialog_frame.dimen
    end)
end

function PromptSelectionDialog:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "ui", self.movable.dimen
    end)
end

return PromptSelectionDialog