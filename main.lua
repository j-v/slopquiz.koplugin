local Dispatcher = require("dispatcher") -- luacheck:ignore
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local ConfirmBox = require("ui/widget/confirmbox")
local logger = require("logger")
local ReaderRolling = require("apps/reader/modules/readerrolling")
local InputDialog = require("ui/widget/inputdialog")
local LLMHandler = require("llm_handler")
local InfoMessage = require("ui/widget/infomessage")
local Trapper = require("ui/trapper")


local SlopQuiz = WidgetContainer:extend {
  name = "slopquiz",
  is_doc_only = false,
}

function SlopQuiz:isEnabled()
  local bookSetting = self.ui.doc_settings:readSetting("slopquiz_enabled")
  if bookSetting ~= nil then
    logger.dbg('SlopQuiz bookSetting ', bookSetting)
    return bookSetting
  else 
    local defaultSetting = G_reader_settings:isTrue("slopquiz_enabled_by_default")
    logger.dbg('SlopQuiz defaultSetting ', defaultSetting)
    self.ui.doc_settings:saveSetting("slopquiz_enabled", defaultSetting)
    return defaultSetting
  end
end

function SlopQuiz:init()  
--   logger.dbg('SlopQuiz enabled: ', self:isEnabled())

  local function isAtChapterEnd()
    return SlopQuiz.isAtChapterEnd(self)
  end

  local function isEnabled()
    return SlopQuiz.isEnabled(self)
  end

  if not ReaderRolling.__chapter_quiz_patched then
    ReaderRolling.__chapter_quiz_patched = true
    ReaderRolling.__chapter_quiz_orig_onGotoViewRel = ReaderRolling.onGotoViewRel

    function ReaderRolling:onGotoViewRel(diff, no_page_turn)
        if isEnabled() and diff == 1 then
            local isAtEnd, start_page, end_page = isAtChapterEnd()
            if isAtEnd then
                UIManager:show(ConfirmBox:new{
                    text = _("End of chapter. Would you like to generate a quiz?"),
                    ok_text = _("Quiz Me"),
                    cancel_text = _("Skip"),
                    ok_callback = function()
                        -- Proceed to next page first? Or stay on the same page. Let's just generate quiz.
                        self.chapter_quiz_plugin:startQuiz(start_page, end_page)
                        
                        -- Also optionally go to next page
                        ReaderRolling.__chapter_quiz_orig_onGotoViewRel(
                            self, diff, no_page_turn
                        )
                    end,
                    cancel_callback = function()
                        ReaderRolling.__chapter_quiz_orig_onGotoViewRel(
                            self, diff, no_page_turn
                        )
                    end,
                })
                return true
            end
        end


        return ReaderRolling.__chapter_quiz_orig_onGotoViewRel(
            self, diff, no_page_turn
        )
    end
  end
  ReaderRolling.chapter_quiz_plugin = self

  self.ui.menu:registerToMainMenu(self)
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
  local doc = self.ui.document
  if not doc then return false end

  -- Get TOC (cached in doc)
  local toc = doc:getToc()
  if not toc or #toc == 0 then return false end

  local current_page = doc:getCurrentPage()
  local total_pages = doc:getPageCount()
  if not current_page or not total_pages then
      return false
  end

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

  local chapter_start_page = toc[current_chapter_idx].page
  local next_chapter = toc[current_chapter_idx + 1]
  local chapter_end_page = next_chapter and (next_chapter.page - 1) or total_pages

  return current_page >= chapter_end_page, chapter_start_page, chapter_end_page
end

function SlopQuiz:addToMainMenu(menu_items)
  -- TODO allow use of config file for settings? (like assistant.koplugin)
  -- TODO option to inherit settings from assistant.koplugin?

  menu_items.slop_quiz = {
    text = _("SlopQuiz Settings"),
    sorting_hint = "tools",
    sub_item_table = {

        {
            text = _("Enable for this book"),
            keep_menu_open = true,
            checked_func = function()
                return self:isEnabled()
            end,
            callback = function()
                local currently_enabled = self:isEnabled()
                self.ui.doc_settings:saveSetting("slopquiz_enabled", not currently_enabled)
            end,
        },
        {
            text = _("Enable by default for new books"),
            keep_menu_open = true,
            checked_func = function()
                return G_reader_settings:isTrue("slopquiz_enabled_by_default")
            end,
            callback = function()
                G_reader_settings:flipNilOrFalse("slopquiz_enabled_by_default")
            end,
            separator = true,
        },
        {
            text = _("API Key"),
            keep_menu_open = true,
            callback = function()
                local inputdialog 
                inputdialog = InputDialog:new {
                    title = _("API Key"),
                    input = G_reader_settings:readSetting("slopquiz_api_key") or "",
                    buttons = {{
                        {
                            text = _("Save"),
                            callback = function(dialog)
                                G_reader_settings:saveSetting("slopquiz_api_key", inputdialog:getInputText())
                                UIManager:close(inputdialog)
                            end,
                        }
                    }}
                }
                UIManager:show(inputdialog)
            end,
        },
        {
            text = _("Model ID"),
            keep_menu_open = true,
            callback = function()
                local inputdialog
                inputdialog = InputDialog:new {
                    title = _("Model"),
                    description= _("Model ID, e.g. gpt-4o-mini, gemini-2.5-flash-lite"),
                    input = G_reader_settings:readSetting("slopquiz_model") or "gpt-4o-mini",
                    buttons = {{
                        {
                            text = _("Save"),
                            callback = function()
                                G_reader_settings:saveSetting("slopquiz_model", inputdialog:getInputText())
                                UIManager:close(inputdialog)
                            end,
                        }
                    }}
                }
              UIManager:show(inputdialog)
            end,
        },
        {
            text = _("API Base URL"),
            keep_menu_open = true,
            callback = function()
                local inputdialog 
                inputdialog = InputDialog:new {
                    title = _("API Base URL"),
                    description = _("OpenAI compatible API endpoint, e.g. https://api.openai.com/v1/chat/completions"),
                    input = G_reader_settings:readSetting("slopquiz_base_url") or "https://api.openai.com/v1/chat/completions",
                    buttons = {{
                        {
                            text = _("Save"),
                            callback = function()
                                G_reader_settings:saveSetting("slopquiz_base_url", inputdialog:getInputText())
                                UIManager:close(inputdialog)
                            end,
                        }
                    }}
                }
                UIManager:show(inputdialog)
            end,
        }
    }
  }
end

function SlopQuiz:startQuiz(start_page, end_page)
    Trapper:wrap(function()
        -- extract text
        local book_text = ""
        if not self.ui.document.info.has_pages then
            -- EPUB / reflowable
            local start_xp = self.ui.document:getPageXPointer(start_page)
            local total_pages = self.ui.document:getPageCount()
            local next_page = end_page + 1
            local end_xp = nil
            if next_page <= total_pages then
                end_xp = self.ui.document:getPageXPointer(next_page)
            end
            
            -- If end_xp is nil (we are at the end of the book), we can just get text to the end.
            -- We'll try to get the XPointer of the last page as a fallback.
            if not end_xp then
                end_xp = self.ui.document:getPageXPointer(total_pages)
            end
            
            if start_xp and end_xp then
                book_text = self.ui.document:getTextFromXPointers(start_xp, end_xp) or ""
            end
        else
            -- PDF / fixed layout
            -- TODO testing needed
            for page = start_page, end_page do
                local page_text = self.ui.document:getPageText(page) or ""
                if type(page_text) == "table" then
                    local texts = {}
                    for _, block in ipairs(page_text) do
                        if type(block) == "table" then
                            for i = 1, #block do
                                local span = block[i]
                                if type(span) == "table" and span.word then
                                    table.insert(texts, span.word)
                                end
                            end
                        end
                    end
                    page_text = table.concat(texts, " ")
                end
                book_text = book_text .. "\n" .. page_text
            end
        end

        local api_key = G_reader_settings:readSetting("slopquiz_api_key") or ""
        local model = G_reader_settings:readSetting("slopquiz_model") or "gpt-4o-mini"
        local base_url = G_reader_settings:readSetting("slopquiz_base_url") or "https://api.openai.com/v1/chat/completions"

        if api_key == "" then
            local InfoMessage = require("ui/widget/infomessage")
            UIManager:show(InfoMessage:new{ text = "Please set SlopQuiz API Key in settings", timeout = 3 })
            return
        end

        -- TODO customizable prompt in settings
        -- TODO option to add book name and author in prompt?
        local prompt = "You are an assistant that generates a reading comprehension quiz based on book chapters. Read the text and generate 3 thought-provoking questions about the events, character motivations, themes, and details in the chapter. Format the output clearly. Here is the chapter text:\n\n" .. book_text

        local trap = InfoMessage:new{
            text = "Generating Quiz...\nModel: " .. model,
        }
        UIManager:show(trap)

        local response, err = LLMHandler.query(api_key, model, base_url, prompt, trap)

        UIManager:close(trap)

        if err then
            UIManager:show(InfoMessage:new{ text = "Failed to generate quiz: " .. tostring(err) })
            return
        end

        UIManager:show(ConfirmBox:new{
            text = response,
            ok_text = _("Close"),
        })
    end)
end

function SlopQuiz:onCloseWidget()
  if ReaderRolling.__chapter_quiz_patched and ReaderRolling.__chapter_quiz_orig_onGotoViewRel then
    ReaderRolling.__chapter_quiz_patched = false

    ReaderRolling.onGotoViewRel = ReaderRolling.__chapter_quiz_orig_onGotoViewRel
    ReaderRolling.__chapter_quiz_orig_onGotoViewRel = nil
  end
end

return SlopQuiz
