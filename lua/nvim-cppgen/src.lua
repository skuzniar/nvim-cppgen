local lib = require('nvim-cppgen.lib')
local log = require('nvim-cppgen.log')

-----
local function tprint (tbl, indent)
  if not indent then indent = 0 end
  local toprint = string.rep(" ", indent) .. "{\r\n"
  indent = indent + 2 
  for k, v in pairs(tbl) do
    toprint = toprint .. string.rep(" ", indent)
    if (type(k) == "number") then
      toprint = toprint .. "[" .. k .. "] = "
    elseif (type(k) == "string") then
      toprint = toprint  .. k ..  "= "   
    end
    if (type(v) == "number") then
      toprint = toprint .. v .. ",\r\n"
    elseif (type(v) == "string") then
      toprint = toprint .. "\"" .. v .. "\",\r\n"
    elseif (type(v) == "table") then
      toprint = toprint .. tprint(v, indent + 2) .. ",\r\n"
    else
      toprint = toprint .. "\"" .. tostring(v) .. "\",\r\n"
    end
  end
  toprint = toprint .. string.rep(" ", indent-2) .. "}"
  return toprint
end

---------------------------------------------------------------------------------------------------
-- Code completion source module. Implements code completion source interface.
---------------------------------------------------------------------------------------------------
--- Exported functions
local M = {}

--- Return new source
M.new = function()
    log.info('new')
    return setmetatable({}, { __index = M })
end

--- Return whether this source is available in the current context or not (optional).
function M:is_available()
    --log.info('is_available')
    return vim.bo.filetype == "cpp" and lib.code_gen_available(vim.api.nvim_get_current_buf())
end

--- Return the debug name of this source (optional).
--[[
function M:get_debug_name()
    log.info('source.get_debug_name')
  return 'cmp-develop'
end
]]

--- Return LSP's PositionEncodingKind (optional).
--[[
function M:get_position_encoding_kind()
    log.info('source.get_position_encoding_kind')
  return 'utf-16'
end
]]

--- Return the keyword pattern for triggering completion (optional).
--[[
function M:get_keyword_pattern()
    log.info('get_keyword_pattern')
    return 'friend'
end
]]

--- Return trigger characters for triggering completion (optional).
--[[
function M:get_trigger_characters()
    log.info('source.get_trigger_characters')
    return { '.' }
end
]]

--- Invoke completion (required).
function M:complete(params, callback)
    log.info('complete')
    --log.info(tprint(params or {}))
    local snips = lib.code_gen(params.context.bufnr, params.context.cursor)
    if snips then
        callback(snips)
    end
end

--- Resolve completion item (optional). This is called right before the completion is about to be displayed.
--[[
function M:resolve(completion_item, callback)
    log.info('resolve')
    callback(completion_item)
end
]]

--- Executed after the item was selected.
--[[
function M:execute(completion_item, callback)
    log.info('execute')
    callback(completion_item)
end
]]

return M

