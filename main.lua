local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local ConfirmBox = require("ui/widget/confirmbox")
local QuizViewer = require("quizviewer")
local logger = require("logger")
local ReaderRolling = require("apps/reader/modules/readerrolling")
local InputDialog = require("ui/widget/inputdialog")
local LLMHandler = require("llm_handler")
local Trapper = require("ui/trapper")
local Event = require("ui/event")
local DocSettings = require("docsettings")
local QuizPrompts = require("quizprompts")
local ProviderSelectionDialog = require("providerselectiondialog")
local PromptSelectionDialog = require("promptselectiondialog")
local Dispatcher = require("dispatcher")

-- configuration locations
local PLUGIN_DIR = string.match(debug.getinfo(1).source, "^@(.*/)")
local CONFIG_FILE_PATH = PLUGIN_DIR .. "config.lua"
local CONFIG_LOAD_ERROR = nil
local CONFIG = nil

local function testConfigFile(filePath)
    local env = {}
    setmetatable(env, {__index = _G})
    local chunk, err = loadfile(filePath, "t", env) -- test mode to loadfile, check syntax errors
    if not chunk then return false, err end
    local success, result = pcall(chunk) -- run the code, checks runtime errors
    if not success then return false, result end
    return true, nil
end

-- Test and load config file
local ok, err = testConfigFile(CONFIG_FILE_PATH)
if not ok then 
    CONFIG_LOAD_ERROR = err 
    logger.warn('Error loading SlopQuiz config file: ', CONFIG_LOAD_ERROR)
else
    local success, result = pcall(function() return dofile(CONFIG_FILE_PATH) end)
    if success then CONFIG = result
    else logger.warn(result) end
end


local function animateLoadingDots(trap, model, intervalSeconds)
    local dots = ""
    local timer
    local function update()
        dots = dots .. "."
        if #dots > 3 then dots = "" end
        local new_text = _("Generating Quiz") .. dots .. "\n" .. _("Model: ") .. model
        trap.text = new_text
        -- Dig into trap.movable to get HorizontalGroup:new{image_widget, span, text_widget}
        local text_widget = trap.movable[1][1][3]
        if text_widget then
            text_widget.text = new_text
            text_widget:free()
            text_widget:init()
            UIManager:setDirty(trap, function()
                return "ui", trap.movable.dimen
            end)
        end
        timer = UIManager:scheduleIn(intervalSeconds, update)
    end
    timer = UIManager:scheduleIn(intervalSeconds, update)
    return function()
        if timer then
            UIManager:unschedule(timer)
            timer = nil
        end
    end
end

local SlopQuiz = WidgetContainer:extend {
  name = "slopquiz",
  is_doc_only = false,
}

function SlopQuiz:init()  
  local function isAtChapterEnd()
    return SlopQuiz.isAtChapterEnd(self)
  end

  local function isEnabled()
    return SlopQuiz.isEnabled(self)
  end

  if not ReaderRolling.__chapter_quiz_patched then
    ReaderRolling.__chapter_quiz_patched = true
    ReaderRolling.__chapter_quiz_orig_onGotoViewRel = ReaderRolling.onGotoViewRel

---@diagnostic disable-next-line: duplicate-set-field
    function ReaderRolling:onGotoViewRel(diff, no_page_turn)
        if isEnabled() and diff == 1 then
            local isAtEnd, start_page, end_page = isAtChapterEnd()
            if isAtEnd then
                UIManager:show(ConfirmBox:new{
                    text = _("End of chapter. How about a quiz?"),
                    ok_text = _("Quiz Me"),
                    cancel_text = _("Skip"),
                    ok_callback = function()
                        -- Proceed to next page first? Or stay on the same page. Let's just generate quiz.
                        local isAtEnd, start_page, end_page, next_chapter_xp = isAtChapterEnd()
                        self.chapter_quiz_plugin:startQuiz(start_page, end_page, next_chapter_xp)
                        
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
  self:onDispatcherRegisterActions()
end

function SlopQuiz:onDispatcherRegisterActions()
  Dispatcher:registerAction("slopquiz_open_chapter_quiz", {
    category = "none",
    event = "SlopQuizOpenChapterQuiz",
    title = _("SlopQuiz: Open chapter quiz"),
    general = true,
  })
end

function SlopQuiz:onSlopQuizOpenChapterQuiz()
  local not_found_message = _("Could not determine current chapter.")
  local _, start_page, end_page, next_chapter_xp = self:isAtChapterEnd()
  if start_page and end_page then
    self:startQuiz(start_page, end_page, next_chapter_xp)
  else
    UIManager:show(InfoMessage:new{
      text = not_found_message
    })
  end
end

function SlopQuiz:isEnabled()
  if self.ui.doc_settings == nil then return false end

  local bookSetting = self.ui.doc_settings:readSetting("slopquiz_enabled")
  if bookSetting ~= nil then
    return bookSetting
  else 
    local defaultSetting = G_reader_settings:isTrue("slopquiz_enabled_by_default")
    self.ui.doc_settings:saveSetting("slopquiz_enabled", defaultSetting)
    return defaultSetting
  end
end

function SlopQuiz:getDocumentInfo()
  local document = self.ui.document
  if document == nil then
    return { }
  end
  local doc_settings = DocSettings:open(document.file)
  local doc_props = doc_settings:child("doc_props")
  local title = doc_props:readSetting("title") or document:getProps().title or "Unknown Title"
  local authors = doc_props:readSetting("authors") or document:getProps().authors or "Unknown Author"
  return {
    title = title,
    authors = authors,
  }
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

  return current_page >= chapter_end_page, chapter_start_page, chapter_end_page, next_chapter and next_chapter.xpointer
end

function SlopQuiz:addToMainMenu(menu_items)
  menu_items.slop_quiz = {
    text = _("SlopQuiz"),
    sorting_hint = "tools",
    sub_item_table = {
        {
            text = _("Open quiz for current chapter"),
            enabled_func = function()
                return self.ui.doc_settings ~= nil
            end,
            callback = function()
                self:onSlopQuizOpenChapterQuiz()
            end,
            separator = true,
        },

        {
            text = _("Enable quiz prompt for this book"),
            keep_menu_open = true,
            enabled_func = function ()
                return self.ui.doc_settings ~= nil
            end,
            checked_func = function()
                return self:isEnabled()
            end,
            callback = function()
                local currently_enabled = self:isEnabled()
                self.ui.doc_settings:saveSetting("slopquiz_enabled", not currently_enabled)
            end,
        },
        {
            text = _("Enable quiz prompt by default for new books"),
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
            text = _("Select LLM provider"),
            enabled_func = function()
                return CONFIG and CONFIG.providers and #CONFIG.providers > 0
            end,
            callback = function()
                local providers = CONFIG and CONFIG.providers
                local dialog
                dialog = ProviderSelectionDialog:new{
                    providers = providers
                }
                UIManager:show(dialog)
            end,
        },
        {
            text = _("Default LLM provider configuration"),
            sub_item_table = {
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
                                    text = _("Cancel"),
                                    callback = function()
                                        UIManager:close(inputdialog)
                                    end,
                                },
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
                                    text = _("Cancel"),
                                    callback = function()
                                        UIManager:close(inputdialog)
                                    end,
                                },
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
                                    text = _("Cancel"),
                                    callback = function()
                                        UIManager:close(inputdialog)
                                    end,
                                },
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
        },
        {
            text = _("Select quiz prompt"),
            callback = function()
                local user_prompts = CONFIG and CONFIG.user_prompts
                local dialog = PromptSelectionDialog:new{
                    user_prompts = user_prompts,
                }
                UIManager:show(dialog)
            end,
        },
    }
  }
end

function SlopQuiz:startQuiz(start_page, end_page, next_chapter_xp)
    local page_to_bookmark
    if not self.ui.document.info.has_pages then
        -- EPUB / reflowable
        if next_chapter_xp then
            page_to_bookmark = self.ui.document.getPrevVisibleChar and self.ui.document:getPrevVisibleChar(next_chapter_xp) or next_chapter_xp
        else
            page_to_bookmark = self.ui.document:getPageXPointer(end_page)
        end
    else
        -- PDF / fixed layout
        page_to_bookmark = end_page
    end

    local quiz_viewer_title = _("Chapter quiz")
    -- Check if a quiz bookmark already exists on this page
    if self.ui.annotation and self.ui.annotation.annotations then
        for i, anno in ipairs(self.ui.annotation.annotations) do
            if anno.page == page_to_bookmark and anno.text and anno.text:find("^SlopQuiz") then
                if anno.note then
                    local viewer = QuizViewer:new{
                        title = quiz_viewer_title,
                        text = anno.note,
                        index = i,
                        ui = self.ui,
                        regenerate_callback = function()
                            self.ui.bookmark:removeItemByIndex(i)
                            self:startQuiz(start_page, end_page, next_chapter_xp)
                        end,
                    }
                    UIManager:show(viewer)
                    return
                end
            end
        end
    end

    Trapper:wrap(function()
        -- extract text
        local chapter_text = ""
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
                chapter_text = self.ui.document:getTextFromXPointers(start_xp, end_xp) or ""
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
                chapter_text = chapter_text .. "\n" .. page_text
            end
        end

        -- TODO handle cases where book_text might be too long

        local provider_name = G_reader_settings:readSetting("slopquiz_provider")
        local api_key, model, base_url
        local provider_config_found = false
        if provider_name ~= nil and provider_name ~= "_default" then
            if CONFIG and CONFIG.providers then
                local providers = CONFIG.providers
                for i = 1, #providers do
                    local provider = providers[i]
                    if provider.name == provider_name then
                        provider_config_found = true
                        api_key = provider.api_key
                        model = provider.model
                        base_url = provider.base_url
                        break
                    end
                end  
            end

            if provider_config_found == false then
                UIManager:show(InfoMessage:new{
                    text = _("Selected provider not found in config.lua. Falling back to default provider.")
                })
                G_reader_settings:saveSetting("slopquiz_provider", "_default")
            end
        end

        if provider_config_found == false then
            api_key = G_reader_settings:readSetting("slopquiz_api_key") or ""
            model = G_reader_settings:readSetting("slopquiz_model") or "gpt-4o-mini"
            base_url = G_reader_settings:readSetting("slopquiz_base_url") or "https://api.openai.com/v1/chat/completions"
        end

        if api_key == "" then
            UIManager:show(InfoMessage:new{ text = "Please set SlopQuiz API Key in settings", timeout = 3 })
            return
        end

        local docInfo = self:getDocumentInfo()

        -- Resolve selected prompt template
        local prompt_id = G_reader_settings:readSetting("slopquiz_prompt_id") or "_default"
        local base_prompt = QuizPrompts.DEFAULT_QUIZ_PROMPT
        -- check built-in prompts
        for _, p in ipairs(QuizPrompts.BUILTIN_PROMPTS) do
            if p.id == prompt_id then
                base_prompt = p.prompt
                break
            end
        end
        -- check user prompts (ids are "_user_<index>")
        if prompt_id:sub(1, 6) == "_user_" then
            local idx = tonumber(prompt_id:sub(7))
            if idx and CONFIG and CONFIG.user_prompts and CONFIG.user_prompts[idx] then
                local user_prompt = CONFIG.user_prompts[idx]
                if type(user_prompt.prompt) == "string" then
                    base_prompt = user_prompt.prompt
                end
            end
        end

        local prompt = base_prompt:gsub(
            QuizPrompts.BOOK_TITLE_VAR, docInfo.title
        ):gsub(
            QuizPrompts.AUTHORS_VAR, docInfo.authors
        ):gsub(
            QuizPrompts.CHAPTER_TEXT_VAR, chapter_text
        )

        local trap = InfoMessage:new{
            text = _("Generating Quiz...") .. "\n" .. _("Model: ") .. model,
        }
        UIManager:show(trap)

        local stopAnimation = animateLoadingDots(trap, model, 0.5)

        local response, err = LLMHandler.query(api_key, model, base_url, prompt, trap)

        stopAnimation()
        UIManager:close(trap)

        if err then
            UIManager:show(InfoMessage:new{ text = "Failed to generate quiz: " .. tostring(err) })
            return
        end

        
        local chapter = self.ui.toc:getTocTitleByPage(page_to_bookmark)
        if chapter == "" then
            chapter = nil
        end
        local text = chapter and 'SlopQuiz: ' .. chapter or 'SlopQuiz'
        local item = {
            page = page_to_bookmark,
            text = text,
            chapter = chapter,
            note = response,
        }
        local index = self.ui.annotation:addItem(item)
        self.ui:handleEvent(Event:new("AnnotationsModified", { item, index_modified = index }))

        local viewer = QuizViewer:new{
            title = quiz_viewer_title,
            text = response,
            index = index,
            ui = self.ui,
            regenerate_callback = function()
                self.ui.bookmark:removeItemByIndex(index)
                self:startQuiz(start_page, end_page, next_chapter_xp)
            end,
        }
        UIManager:show(viewer)
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
