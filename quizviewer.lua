local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Geom = require("ui/geometry")
local FrameContainer = require("ui/widget/container/framecontainer")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local MovableContainer = require("ui/widget/container/movablecontainer")
local ScrollHtmlWidget = require("ui/widget/scrollhtmlwidget")
local Size = require("ui/size")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local Screen = Device.screen
local MD = require("apps/filemanager/lib/md")

local VIEWER_CSS = [[
@page {
    margin: 0;
    font-family: 'Noto Sans CJK TC', 'Noto Sans Arabic', 'Noto Sans Devanagari UI', 'Noto Sans Bengali UI', 'FreeSans', 'Noto Sans', sans-serif;
}

body {
    margin: 0;
    line-height: 1.25;
    padding: 0;
}

blockquote, dd, pre {
    margin: 0 1em;
}

ol, ul, menu {
    margin: 0;
    padding-left: 1.5em;
}

ul {
    list-style-type: circle;
}

ul ul {
    list-style-type: square;
}

ul ul ul {
    list-style-type: disc;
}

ul li a {
    display: inline-block;
}

table {
    margin: 0;
    padding: 0;
    border-collapse: collapse;
    border-spacing: 0;
    font-size: 0.8em;
}

table td, table th {
    border: 1px solid black;
    padding: 0;
}
]]

local QuizViewer = InputContainer:extend{
    title = nil,
    text = nil,
    width = nil,
    height = nil,
    buttons_table = nil,
    title_face = nil,
    title_multilines = nil,
    title_shrink_font_to_fit = nil,
    fgcolor = Blitbuffer.COLOR_BLACK,
    text_padding = Size.padding.large,
    text_margin = Size.margin.small,
    button_padding = Size.padding.default,
    item = nil,
    ui = nil,
    index = nil,
}

function QuizViewer:init()
    local screen_w = Screen:getWidth()
    local screen_h = Screen:getHeight()

    self.align = "center"
    self.region = Geom:new{
        w = screen_w,
        h = screen_h,
    }
    self.width = self.width or screen_w - Screen:scaleBySize(30)
    self.height = self.height or screen_h - Screen:scaleBySize(30)

    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end

    if Device:isTouchDevice() then
        local range = Geom:new{
            w = screen_w,
            h = screen_h,
        }
        self.ges_events = {
            TapClose = {
                GestureRange:new{
                    ges = "tap",
                    range = range,
                },
            },
            Swipe = {
                GestureRange:new{
                    ges = "swipe",
                    range = range,
                },
            },
            MultiSwipe = {
                GestureRange:new{
                    ges = "multiswipe",
                    range = range,
                },
            },
            HoldStartText = {
                GestureRange:new{
                    ges = "hold",
                    range = range,
                },
            },
            HoldPanText = {
                GestureRange:new{
                    ges = "hold",
                    range = range,
                },
            },
            HoldReleaseText = {
                GestureRange:new{
                    ges = "hold_release",
                    range = range,
                },
            },
            ForwardingTouch = { GestureRange:new{ ges = "touch", range = range, }, },
            ForwardingPan = { GestureRange:new{ ges = "pan", range = range, }, },
            ForwardingPanRelease = { GestureRange:new{ ges = "pan_release", range = range, }, },
        }
    end

    self.titlebar = TitleBar:new{
        width = self.width,
        align = "left",
        with_bottom_line = true,
        title = self.title,
        title_face = self.title_face,
        title_multilines = self.title_multilines,
        title_shrink_font_to_fit = self.title_shrink_font_to_fit,
        close_callback = function() self:onClose() end,
        show_parent = self,
    }

    local prev_at_top = false
    local prev_at_bottom = false
    local function button_update(id, enable)
        local button = self.button_table:getButtonById(id)
        if button then
            if enable then
                button:enable()
            else
                button:disable()
            end
            button:refresh()
        end
    end
    self._buttons_scroll_callback = function(low, high)
        if prev_at_top and low > 0 then
            button_update("top", true)
            prev_at_top = false
        elseif not prev_at_top and low <= 0 then
            button_update("top", false)
            prev_at_top = true
        end
        if prev_at_bottom and high < 1 then
            button_update("bottom", true)
            prev_at_bottom = false
        elseif not prev_at_bottom and high >= 1 then
            button_update("bottom", false)
            prev_at_bottom = true
        end
    end

    local default_buttons = {
        {
            text = "⇱",
            id = "top",
            callback = function()
                self.html_viewer:scrollToRatio(0)
            end,
            allow_hold_when_disabled = true,
        },
        {
            text = "⇲",
            id = "bottom",
            callback = function()
                self.html_viewer:scrollToRatio(1)
            end,
            allow_hold_when_disabled = true,
        },
        {
            text = _("Edit"),
            enabled = function() return self.ui and self.ui.bookmark and (self.item or self.index) end,
            callback = function()
                self:onEdit()
            end,
        },
        {
            text = _("Close"),
            callback = function()
                self:onClose()
            end,
        },
    }

    local buttons = self.buttons_table or {}
    table.insert(buttons, default_buttons)

    self.button_table = ButtonTable:new{
        width = self.width - 2*self.button_padding,
        buttons = buttons,
        zero_sep = true,
        show_parent = self,
    }

    local text_frame_height = self.height - self.titlebar:getHeight() - self.button_table:getSize().h

    local html_body, err = MD(self.text or "")
    if err then
        html_body = self.text or ""
    end

    self.html_viewer = ScrollHtmlWidget:new{
        html_body = html_body,
        css = VIEWER_CSS,
        default_font_size = Screen:scaleBySize(20),
        width = self.width - 2*self.text_padding - 2*self.text_margin,
        height = text_frame_height - 2*self.text_padding - 2*self.text_margin,
        dialog = self,
    }
    
    self.text_frame = FrameContainer:new{
        padding = self.text_padding,
        margin = self.text_margin,
        bordersize = 0,
        self.html_viewer
    }

    self.frame = FrameContainer:new{
        radius = Size.radius.window,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            self.titlebar,
            CenterContainer:new{
                dimen = Geom:new{
                    w = self.width,
                    h = self.text_frame:getSize().h,
                },
                self.text_frame,
            },
            CenterContainer:new{
                dimen = Geom:new{
                    w = self.width,
                    h = self.button_table:getSize().h,
                },
                self.button_table,
            }
        }
    }

    self.movable = MovableContainer:new{
        ignore_events = {
            "swipe", "hold", "hold_release", "hold_pan",
            "touch", "pan", "pan_release",
        },
        anchor = self.anchor,
        self.frame,
    }

    -- Set the root child
    self[1] = WidgetContainer:new{
        align = self.align,
        dimen = self.region,
        self.movable,
    }
end

function QuizViewer:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "partial", self.frame.dimen
    end)
end

function QuizViewer:onShow()
    UIManager:setDirty(self, function()
        return "partial", self.frame.dimen
    end)
    return true
end

function QuizViewer:onTapClose(arg, ges_ev)
    if ges_ev.pos:notIntersectWith(self.frame.dimen) then
        self:onClose()
    end
    return true
end

function QuizViewer:onMultiSwipe(arg, ges_ev)
    self:onClose()
    return true
end

function QuizViewer:onClose()
    UIManager:close(self)
    if self.close_callback then
        self.close_callback()
    end
    return true
end

function QuizViewer:onEdit()
    if not self.ui or not self.ui.bookmark then return end
    local item_or_index = self.index or self.item
    self.ui.bookmark:setBookmarkNote(item_or_index, false, nil, function()
        if self.item then
            self.text = self.item.note
        elseif self.index then
            local annotation = self.ui.annotation.annotations[self.index]
            self.text = annotation and annotation.note or self.text
        end
        self:updateText()
    end)
end

function QuizViewer:updateText()
    local html_body, err = MD(self.text or "")
    if err then
        html_body = self.text or ""
    end
    self.html_viewer.html_body = html_body
    self.html_viewer:init()
    UIManager:setDirty(self, "partial")
end

function QuizViewer:onSwipe(arg, ges)
    if ges.pos:intersectWith(self.text_frame.dimen) then
        local direction = BD.flipDirectionIfMirroredUILayout(ges.direction)
        if direction == "west" then
            self.html_viewer:scrollText(1)
            return true
        elseif direction == "east" then
            self.html_viewer:scrollText(-1)
            return true
        else
            UIManager:setDirty(nil, "full")
            return false
        end
    end
    return self.movable:onMovableSwipe(arg, ges)
end

function QuizViewer:onHoldStartText(_, ges)
    return self.movable:onMovableHold(_, ges)
end

function QuizViewer:onHoldPanText(_, ges)
    if self.movable._touch_pre_pan_was_inside then
        return self.movable:onMovableHoldPan(_, ges)
    end
end

function QuizViewer:onHoldReleaseText(_, ges)
    return self.movable:onMovableHoldRelease(_, ges)
end

function QuizViewer:onForwardingTouch(arg, ges)
    if not ges.pos:intersectWith(self.text_frame.dimen) then
        return self.movable:onMovableTouch(arg, ges)
    else
        self.movable._touch_pre_pan_was_inside = false
    end
end

function QuizViewer:onForwardingPan(arg, ges)
    if self.movable._touch_pre_pan_was_inside or self.movable._moving then
        return self.movable:onMovablePan(arg, ges)
    end
end

function QuizViewer:onForwardingPanRelease(arg, ges)
    if ges.from_mousewheel and ges.relative and ges.relative.y then
        if ges.relative.y < 0 then
            self.html_viewer:scrollText(1)
        elseif ges.relative.y > 0 then
            self.html_viewer:scrollText(-1)
        end
        return true
    end
    return self.movable:onMovablePanRelease(arg, ges)
end

return QuizViewer
