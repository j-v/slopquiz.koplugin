local logger = require("logger")
local http = require("socket.http")
local ltn12 = require("ltn12")
local socket = require("socket")
local socketutil = require("socketutil")
local https = require("ssl.https")
local json = require("json")
local Trapper = require("ui/trapper")
local _ = require("gettext")
local koutil = require("util")

local LLMHandler = {}

-- Helper to make HTTP POST requests with a timeout
local function postURLContent(url, headers, body, timeout, maxtime)
    if string.sub(url, 1, 8) == "https://" then
        https.cert_verify = false  -- disable CA verify
    end

    local sink = {}
    socketutil:set_timeout(timeout, maxtime)
    local request = {
        url = url,
        method = "POST",
        headers = headers or {},
        source = ltn12.source.string(body or ""),
        sink = maxtime and socketutil.table_sink(sink) or ltn12.sink.table(sink),
    }

    local code, response_headers, status = socket.skip(1, http.request(request))
    socketutil:reset_timeout()
    local content = table.concat(sink)

    if code == socketutil.TIMEOUT_CODE or code == socketutil.SSL_HANDSHAKE_CODE or code == socketutil.SINK_TIMEOUT_CODE then
        return false, code, "Request interrupted/timed out"
    end

    if response_headers == nil then
        return false, "NETWORK_ERROR", "Network Error: " .. (status or code or "unknown")
    end

    if response_headers and response_headers["content-length"] then
        local content_length = tonumber(response_headers["content-length"])
        if #content ~= content_length then
            return false, code, "Incomplete content received"
        end
    end
    return true, code, content
end

-- Make request wrapped in Trapper to prevent blocking UI
function LLMHandler.makeRequest(url, headers, body, trap_widget, timeout, maxtime)

    local completed, success, code, content
    if trap_widget then
        local request_timeout = timeout or 45
        local request_maxtime = maxtime or 120
        completed, success, code, content = Trapper:dismissableRunInSubprocess(function()
            return postURLContent(url, headers, body, request_timeout, request_maxtime)
        end, trap_widget)
        if not completed then
            return false, "USER_CANCELED", "Cancelled by user"
        end
    else
        success, code, content = postURLContent(url, headers, body, timeout or 20, maxtime or 45)
    end
    return success, code, content
end

-- Parse and format payload according to the selected OpenAI-compatible endpoint
function LLMHandler.query(api_key, model, base_url, prompt_text, trap_widget)
    if not api_key or api_key == "" then
        return nil, _("API Key is completely missing")
    end
    if not base_url or base_url == "" then
        return nil, _("API Base URL is missing")
    end

    local url = base_url
    local headers = {
        ["Content-Type"] = "application/json"
    }
    local body_table = {}

    headers["Authorization"] = "Bearer " .. api_key
    body_table = {
        model = model,
        messages = {
            { role = "user", content = prompt_text }
        }
    }

    local request_body = json.encode(body_table)
    headers["Content-Length"] = tostring(#request_body)

    local success, code, response = LLMHandler.makeRequest(url, headers, request_body, trap_widget, 60, 180)

    if success then
        local ok, responseData = pcall(json.decode, response)
        if ok and type(responseData) == "table" then
            local error_msg = koutil.tableGetValue(responseData, "error", "message")
            if error_msg then
                return nil, _("API Error: ") .. error_msg
            end

            local result_text = nil
            result_text = koutil.tableGetValue(responseData, "choices", 1, "message", "content")

            if result_text then
                return result_text, nil
            end
        end
        return nil, _("Failed to parse response: ") .. (code or "unknown") .. " - " .. tostring(response)
    end

    return nil, _("Request Failed: ") .. (code or "unknown") .. " - " .. tostring(response)
end

return LLMHandler
