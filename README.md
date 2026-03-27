# SlopQuiz

Want to improve your reading comprehension? Why not try using AI slop? SlopQuiz is a KOReader plugin that shows you LLM-generated powered quizzes at the end of each chapter using any OpenAI-compatible LLM API.

![slopquiz-demo-2](https://github.com/user-attachments/assets/5304988e-1ceb-4603-8dbb-3b865a47e744)

## How it works

When you reach the last page of a chapter and turn the page, SlopQuiz intercepts the page turn and offers you a quiz. It extracts the chapter text, sends it to your configured LLM provider with a customizable prompt, and displays the generated quiz in a scrollable viewer. The quiz is saved as a bookmark annotation at the end of the chapter so it can be retrieved instantly on subsequent visits without another API call. You can edit to add your answers, or re-generate the quiz at any time from the viewer.

> **Note:** By sending the entire chapter text to your LLM provider, you could potentially impact your token usage quota

## Installation

1. Download the [latest release](https://github.com/j-v/slopquiz.koplugin/releases) and unzip it
1. Copy the `slopquiz.koplugin` folder into KOReader's `plugins/` directory.
2. Restart KOReader. The plugin will appear under **Tools → SlopQuiz** in the reader menu.

## LLM Provider Configuration

SlopQuiz supports two ways to configure your LLM provider.

### Option A: Menu (single provider, no file editing)

Open the reader menu and navigate to **Tools → SlopQuiz → Default LLM provider configuration**. Set:

- **API Key** – your provider's API key
- **Model ID** – the model identifier (e.g. `gpt-4o-mini`, `gemini-2.5-flash`)
- **API Base URL** – the OpenAI-compatible chat completions endpoint (e.g. `https://api.openai.com/v1/chat/completions`)

This configuration is used whenever no config-file provider is selected.

> **Note:** Entering your API key on an e-ink device key can be made easier using the [RemoteNote](https://github.com/j-v/remotenote.koplugin) plugin 

### Option B: `config.lua` (multiple providers)

Copy `config.sample.lua` to `config.lua` inside the plugin directory and uncomment / add provider entries:

```lua
local CONFIGURATION = {
    providers = {
        {
            name = "gemini-2.5-flash",
            model = "gemini-2.5-flash",
            base_url = "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
            api_key = "your-api-key",
        },
        {
            name = "gpt-4o-mini",
            model = "gpt-4o-mini",
            base_url = "https://api.openai.com/v1/chat/completions",
            api_key = "your-openai-api-key",
        },
    },
    -- Optional: add your own prompt templates (see Prompts section below)
    user_prompts = {},
}

return CONFIGURATION
```

Any provider with an OpenAI-compatible `/chat/completions` endpoint works, including local models via Ollama or LM Studio.

## Usage

### Enabling the page-turn quiz prompt

Open the reader menu (**tap the centre of the screen**) and go to **Tools → SlopQuiz**:

- **Enable quiz prompt for this book** – toggles the end-of-chapter prompt for the currently open book.
- **Enable quiz prompt by default for new books** – sets the default for books you open in the future.

When enabled, turning past the last page of a chapter will show a confirmation dialog asking if you want a quiz.

### Selecting an LLM provider

Go to **Tools → SlopQuiz → Select LLM provider** (only visible when `config.lua` defines at least one provider). Choose a provider from the list. To revert to the menu-configured defaults, select **Default**.

### Selecting a quiz prompt

Go to **Tools → SlopQuiz → Select quiz prompt**. You can choose from:

- The built-in default prompt (multiple-choice comprehension questions)
- Additional built-in prompt styles
- Custom prompts defined in `config.lua`

#### Custom prompts in `config.lua`

Add entries to the `user_prompts` table. Three variables are substituted at runtime:

| Variable | Description |
|---|---|
| `$CHAPTER_TEXT` | Full text of the current chapter |
| `$BOOK_TITLE` | Title of the book |
| `$AUTHORS` | Author(s) of the book |

Example:

```lua
user_prompts = {
    {
        name = "True/False quiz",
        prompt = "You are a reading comprehension tutor. Present the reader with "
                 .. "a set of true or false questions based on the following chapter "
                 .. "from '$BOOK_TITLE' by $AUTHORS:\n$CHAPTER_TEXT",
    },
}
```

### Opening the chapter quiz on demand

Go to **Tools → SlopQuiz → Open quiz for current chapter** to generate (or view a cached) quiz for whichever chapter you are currently reading, without waiting for a page turn.

### Binding the quiz to a gesture

1. Open the KOReader gesture manager.
2. Tap the gesture zone you want to use.
3. Scroll through the `General` action list and select **SlopQuiz: Open chapter quiz**.

The action opens the quiz for the current chapter, identical to the menu item above.
