local log = require("codecompanion.utils.log")

---Prepare data to be parsed as JSON
---@param data string | { body: string }
---@return string
local prepare_data_for_json = function(data)
  if type(data) == "table" then
    return data.body
  end
  local find_json_start = string.find(data, "{") or 1
  return string.sub(data, find_json_start)
end

--@class OpenRouter.Adapter: CodeCompanion.Adapter
return {
  name = "openrouter",
  roles = {
    llm = "assistant",
    user = "user",
  },
  opts = {
    stream = true,
  },
  features = {
    text = true,
    tokens = true,
    vision = false, -- Most OpenRouter models don't support vision
  },
  url = "https://openrouter.ai/api/v1/chat/completions",
  env = {
    api_key = "OPEN_ROUTER_API_KEY",
  },
  headers = {
    ["Content-Type"] = "application/json",
    Authorization = "Bearer ${api_key}",
    ["HTTP-Referer"] = "https://github.com/yourusername/codecompanion.nvim",
    ["X-Title"] = "codecompanion.nvim",
  },
  handlers = {
    setup = function(self)
      if self.opts and self.opts.stream then
        self.parameters.stream = true
      end
      return true
    end,

    form_parameters = function(self, params, messages)
      return params
    end,

    form_messages = function(self, messages)
      local processed = {}

      for _, msg in ipairs(messages) do
        local role = msg.role
        -- Map LLM role to assistant
        if role == self.roles.llm then
          role = "assistant"
        end

        local last = processed[#processed]
        if last and last.role == role then
          last.content = last.content .. "\n\n" .. msg.content
        else
          table.insert(processed, {
            role = role,
            content = msg.content
          })
        end
      end

      return { messages = processed }
    end,

    tokens = function(self, data)
      if data and data ~= "" then
        local data_mod = prepare_data_for_json(data)
        local ok, json = pcall(vim.json.decode, data_mod, { luanil = { object = true } })

        if ok and json.usage then
          local tokens = json.usage.total_tokens
          log:trace("Tokens: %s", tokens)
          return tokens
        end
      end
    end,

    chat_output = function(self, data)
      local output = {}

      if data and data ~= "" then
        local data_mod = prepare_data_for_json(data)
        local ok, json = pcall(vim.json.decode, data_mod, { luanil = { object = true } })

        if ok and json.choices and #json.choices > 0 then
          local choice = json.choices[1]
          local delta = (self.opts and self.opts.stream) and choice.delta or choice.message

          if delta then
            output.role = delta.role or nil
            output.content = delta.content or ""

            return {
              status = "success",
              output = output,
            }
          end
        end
      end
    end,

    inline_output = function(self, data, context)
      if data and data ~= "" then
        data = prepare_data_for_json(data)
        local ok, json = pcall(vim.json.decode, data, { luanil = { object = true } })

        if ok and json.choices and #json.choices > 0 then
          local choice = json.choices[1]
          local delta = (self.opts and self.opts.stream) and choice.delta or choice.message
          return delta.content or ""
        end
      end
    end,

    on_exit = function(self, data)
      if data.status >= 400 then
        log:error("OpenRouter Error [%d]: %s", data.status, data.body)
      end
    end,
  },
  schema = {
    model = {
      order = 1,
      mapping = "parameters",
      type = "string",
      desc = "Model ID from OpenRouter (e.g., 'openai/gpt-3.5-turbo', 'anthropic/claude-2')",
      default = "openai/gpt-3.5-turbo",
    },
    temperature = {
      order = 2,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 0.7,
      desc = "Sampling temperature (0-2). Higher values = more creative, lower = more focused.",
      validate = function(n)
        return n >= 0 and n <= 2, "Must be between 0 and 2"
      end,
    },
    top_p = {
      order = 3,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 1,
      desc = "Nucleus sampling: consider only top_p probability mass.",
      validate = function(n)
        return n >= 0 and n <= 1, "Must be between 0 and 1"
      end,
    },
    max_tokens = {
      order = 4,
      mapping = "parameters",
      type = "integer",
      optional = true,
      default = 2048,
      desc = "Maximum number of tokens to generate",
      validate = function(n)
        return n > 0, "Must be greater than 0"
      end,
    },
    stop = {
      order = 5,
      mapping = "parameters",
      type = "list",
      optional = true,
      default = nil,
      subtype = {
        type = "string",
      },
      desc = "Up to 4 stop sequences",
      validate = function(l)
        return #l <= 4, "Maximum 4 stop sequences"
      end,
    },
    frequency_penalty = {
      order = 6,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 0,
      desc = "Penalize new tokens based on frequency (-2 to 2)",
      validate = function(n)
        return n >= -2 and n <= 2, "Must be between -2 and 2"
      end,
    },
    presence_penalty = {
      order = 7,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 0,
      desc = "Penalize new tokens based on presence (-2 to 2)",
      validate = function(n)
        return n >= -2 and n <= 2, "Must be between -2 and 2"
      end,
    },
  },
}
