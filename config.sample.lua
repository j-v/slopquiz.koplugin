local CONFIGURATION = {
    providers = {
        -- {
        --     name = "gemini-2.5-flash",
        --     model = "gemini-2.5-flash",
        --     base_url = "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
        --     api_key = "your-api-key"
        -- },
        -- {
        --     name = "gemini-3.1-flash-lite",
        --     model = "gemini-3.1-flash-lite-preview",
        --     base_url = "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
        --     api_key = "your-api-key"
        -- },
        -- {
        --     name = "gpt-4o-mini",
        --     model = "gpt-4o-mini",
        --     base_url = "https://api.openai.com/v1/chat/completions",
        --     api_key = "your-openai-api-key",
        -- }
    },
    -- prompt variables: $CHAPTER_TEXT $AUTHORS $BOOK_TITLE
    user_prompts = {
        -- {
        --     name = 'test prompt',
        --     prompt = 'You are a reading comprehension tutor. Present the reader with a set of true or false questions based on the following chapter text: $CHAPTER_TEXT'
        -- },
    }
}

return CONFIGURATION
