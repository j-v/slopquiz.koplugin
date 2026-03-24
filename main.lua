local Dispatcher = require("dispatcher") -- luacheck:ignore
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local ConfirmBox = require("ui/widget/confirmbox")
local logger = require("logger")
-- local ReaderPaging = require("apps/reader/modules/readerpaging")
local ReaderRolling= require("apps/reader/modules/readerrolling")

local SlopQuiz = WidgetContainer:extend {
  name = "hello",
  is_doc_only = false,
}

function SlopQuiz:onDispatcherRegisterActions()
  Dispatcher:registerAction("helloworld_action",
    { category = "none", event = "SlopQuizWorld", title = _("Hello World"), general = true, })
end

function SlopQuiz:init()
  logger.dbg('SlopQuiz: INIT')
  -- local function patch(tbl, method_name, label)
  --   if not tbl or type(tbl[method_name]) ~= "function" then
  --       logger.dbg("SLOPQUIZ no method", label, method_name)
  --       return
  --   end
  --   local orig_name = "__orig_" .. method_name .. "_" .. label
  --   if tbl[orig_name] then
  --       return
  --   end
  --   tbl[orig_name] = tbl[method_name]
  --   tbl[method_name] = function(self, ...)
  --       logger.dbg("SLOPQUIZ PATCH HIT:", label, method_name, ...)
  --       return tbl[orig_name](self, ...)
  --   end
  --   logger.dbg("SLOPQUIZ patched", label, method_name)
  -- end
  --
  -- local ok1, ReaderPaging = pcall(require, "apps/reader/modules/readerpaging")
  -- if ok1 then
  --     patch(ReaderPaging, "onGotoViewRel", "ReaderPaging")
  --     patch(ReaderPaging, "onGotoPosRel", "ReaderPaging")
  -- end
  --
  -- local ok2, ReaderRolling = pcall(require, "apps/reader/modules/readerrolling")
  -- if ok2 then
  --     patch(ReaderRolling, "onGotoViewRel", "ReaderRolling")
  --     patch(ReaderRolling, "onGotoPosRel", "ReaderRolling")
  -- end
  local function isAtChapterEnd ()
    return SlopQuiz.isAtChapterEnd(self)
  end

  if not ReaderRolling.__chapter_quiz_patched then
    logger.dbg('SlopQUIz - patching onGotoViewRel')
    ReaderRolling.__chapter_quiz_patched = true
    ReaderRolling.__chapter_quiz_orig_onGotoViewRel = ReaderRolling.onGotoViewRel

    function ReaderRolling:onGotoViewRel(diff, no_page_turn)
      local isAtChapterEndRes = isAtChapterEnd()
        logger.dbg("SlopQuiz: patched onGotoViewRel", diff, isAtChapterEndRes)

        -- if diff == 1 and self.chapter_quiz_plugin and self:isAtChapterEnd() then
        if diff == 1 and isAtChapterEndRes then
            UIManager:show(ConfirmBox:new{
                text = _("End of chapter"),
                ok_text = _("Continue"),
                ok_callback = function()
                    ReaderRolling.__chapter_quiz_orig_onGotoViewRel(
                        self, diff, no_page_turn
                    )
                end,
            })
            return true
        end

        return ReaderRolling.__chapter_quiz_orig_onGotoViewRel(
            self, diff, no_page_turn
        )
    end
  end
  self:onDispatcherRegisterActions()
  self.ui.menu:registerToMainMenu(self)
end

-- function SlopQuiz:onPageUpdate()
--   logger.dbg('SLOPQUIZ ONPAGEUPDATE')
--   -- recompute chapter progress here
--   if self:isAtChapterEnd() then
--     self:showQuizDialog()
--   end
--   return false   -- let event propagate
-- end
-- function SlopQuiz:onPosUpdate()
--   logger.dbg('SLOPQUIZ ONPOSUPDATE')
--   -- recompute chapter progress here
--   if self:isAtChapterEnd() then
--     self:showQuizDialog()
--   end
--   return false   -- let event propagate
-- end
--
function SlopQuiz:onLayoutChange()
  -- recheck if layout change pushed us to boundary
  -- if self:isAtChapterEnd() then
  --   self:showQuizDialog()
  -- end
  return false
end

function SlopQuiz:showQuizDialog()
  local dlg = ConfirmBox:new {
    text = _("Start quiz for this chapter?"),
    ok_text = _("Start"),
    cancel_text = _("Later"),
    ok_callback = function()
      -- your quiz UI here (another dialog or custom widget)
    end,
  }
  UIManager:show(dlg)
end

function SlopQuiz:isAtChapterEnd()
  logger.dbg('SlopQuiz:isAtChapterEnd')
  local doc = self.ui.document   -- or self.parent.ui.document if nested
  if not doc then return false end

  -- # TODO getDocument is nil
  -- local doc = reader:getDocument()
  -- if not doc then return false end

  logger.dbg('SlopQuiz:isAtChapterEnd')
  -- Get TOC (cached in doc)
  local toc = doc:getToc()
  if not toc or #toc == 0 then return false end

  logger.dbg('SlopQuiz:isAtChapterEnd')
  local current_page = doc:getCurrentPage()
  local total_pages = doc:getPageCount()
  if not current_page or not total_pages then
      return false
  end

  logger.dbg('SlopQuiz:isAtChapterEnd')
  local current_chapter_idx = nil
  for i = 1, #toc do
      local chapter_start = toc[i].page
      local next_chapter = toc[i + 1]
      local chapter_end = next_chapter and next_chapter.page or (total_pages + 1)

      if current_page >= chapter_start and current_page < chapter_end then
          current_chapter_idx = i
          break
      end
  end

  if not current_chapter_idx then
      return false
  end

  -- local chapter_start_page = toc[current_chapter_idx].page
  local next_chapter = toc[current_chapter_idx + 1]
  local chapter_end_page = next_chapter and (next_chapter.page - 1) or total_pages

  logger.dbg('SLOPQUIZ current_page: ', current_page, ' total_pages: ', total_pages, ' current_chapter_idx: ', current_chapter_idx, 
    ' chapter_end_page: ', chapter_end_page);
  return current_page >= chapter_end_page
end

function SlopQuiz:addToMainMenu(menu_items)
  menu_items.hello_world = {
    text = _("SlopQuiz World"),
    -- in which menu this should be appended
    sorting_hint = "more_tools",
    -- a callback when tapping
    callback = function()
      UIManager:show(InfoMessage:new {
        text = _("SlopQuiz, plugin world"),
      })
    end,
  }
end

function SlopQuiz:onCloseWidget()
  logger.dbg('SlopQuiz onCloseWidget')
  if ReaderRolling.__chapter_quiz_patched and ReaderRolling.__chapter_quiz_orig_onGotoViewRel then
    logger.dbg('SlopQuiz unpatching')
    ReaderRolling.__chapter_quiz_patched = false

    ReaderRolling.onGotoViewRel = ReaderRolling.__chapter_quiz_orig_onGotoViewRel
    ReaderRolling.__chapter_quiz_orig_onGotoViewRel = nil
  end
end

return SlopQuiz
