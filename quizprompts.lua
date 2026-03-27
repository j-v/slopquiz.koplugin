local _ = require("gettext")

local QUIZ_PROMPTS = {
    CHAPTER_TEXT_VAR = "$CHAPTER_TEXT",
    AUTHORS_VAR = "$AUTHORS",
    BOOK_TITLE_VAR ="$BOOK_TITLE",
}

QUIZ_PROMPTS.DEFAULT_QUIZ_PROMPT = [[You are an assistant that generates a reading 
comprehension quiz based on book chapters. Read the text and generate 3 thought-provoking 
questions about the events, character motivations, themes, and details in the chapter. 
Format the output clearly. Here is the chapter text:\n\n"]] .. QUIZ_PROMPTS.CHAPTER_TEXT_VAR

QUIZ_PROMPTS.BUILTIN_PROMPTS = {
    {
        id = "_default",
        name = _("Default (comprehension quiz)"),
        prompt = QUIZ_PROMPTS.DEFAULT_QUIZ_PROMPT,
    },
    {
        id = "_multipleChoice",
        name = _("Multiple choice quiz"),
        prompt = "You are a testing the reader of the book \"" .. QUIZ_PROMPTS.BOOK_TITLE_VAR .. "\" by " .. QUIZ_PROMPTS.AUTHORS_VAR .. "\" on comprehension of the current chapter. Provide a multiple choice test of 3 to 10 questions based on the content. Here is the chapter text:\n\n" .. QUIZ_PROMPTS.CHAPTER_TEXT_VAR,
    },
    {
        id = "_vocabulary",
        name = _("Vocabulary & language focus"),
        prompt = "You are a vocabulary tutor. From the following chapter of \"" .. QUIZ_PROMPTS.BOOK_TITLE_VAR .. "\" by " .. QUIZ_PROMPTS.AUTHORS_VAR .. ", identify 5 notable words or phrases. For each, give a short example sentence showing its use in context and prompt the reader to provide a definition. Here is the chapter text:\n\n" .. QUIZ_PROMPTS.CHAPTER_TEXT_VAR,
    },
    {
        id = "_themes",
        name = _("Themes & critical analysis"),
        prompt = "You are a literary critic. Analyse the following chapter from \"" .. QUIZ_PROMPTS.BOOK_TITLE_VAR .. "\" by " .. QUIZ_PROMPTS.AUTHORS_VAR .. ". Identify 2-3 key themes or motifs at work in this chapter, explain how they are developed, and pose one discussion question inviting the reader's interpretation. Here is the chapter text:\n\n" .. QUIZ_PROMPTS.CHAPTER_TEXT_VAR,
    },
}

return QUIZ_PROMPTS