local gen = require('cppgen.gen')
local log = require('cppgen.log')

---------------------------------------------------------------------------------------------------
-- Code completion source module.
-- 1. Implements code completion source interface.
-- 2. Implements code genration interface.
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Global parameters for code generation.
---------------------------------------------------------------------------------------------------
local G = {}

--- Exported functions
local M = {}

--- Return new source
function M:new()
    log.trace('new')
    return setmetatable({}, { __index = M })
end

--- Return whether this source is available in the current context or not (optional).
function M:is_available()
    log.trace('is_available')
    return gen.available(vim.api.nvim_get_current_buf())
end

--- Return the debug name of this source (optional).
--[[
function M:get_debug_name()
    log.trace('get_debug_name')
    return 'c++gen'
end
]]

--- Return LSP's PositionEncodingKind (optional).
--[[
function M:get_position_encoding_kind()
    log.trace('get_position_encoding_kind')
  return 'utf-16'
end
]]

--- Return the keyword pattern for triggering completion (optional).
--[[
function M:get_keyword_pattern()
    log.trace('get_keyword_pattern')
    return 'friend'
end
]]

--- Return trigger characters for triggering completion (optional).
--[[
function M:get_trigger_characters()
    log.trace('get_trigger_characters')
    return { '.' }
end
]]

--- Invoke completion (required).
function M:complete(params, callback)
    log.trace('complete:', params)
    local items = gen.generate(params.context.bufnr)
    if items then
        if G.disclaimer and string.len(G.disclaimer) > 0 then
            for _,item in ipairs(items) do
                item.insertText = G.disclaimer .. '\n' .. item.insertText
            end
        end
        callback(items)
    end
end

--- Resolve completion item (optional). This is called right before the completion is about to be displayed.
--[[
function M:resolve(completion_item, callback)
    log.trace('resolve')
    callback(completion_item)
end
]]

--- Executed after the item was selected.
--[[
function M:execute(completion_item, callback)
    log.trace('execute')
    callback(completion_item)
end
]]

---------------------------------------------------------------------------------------------------
--- Initialization callback
---------------------------------------------------------------------------------------------------
function M.setup(opts)
    G.disclaimer = opts.disclaimer or ''
    gen.setup(opts)
end

---------------------------------------------------------------------------------------------------
--- Info callback
---------------------------------------------------------------------------------------------------
function M.info()
    return gen.info()
end

---------------------------------------------------------------------------------------------------
--- Code generation callbacks
---------------------------------------------------------------------------------------------------
function M.attached(client, bufnr)
    log.trace("Attached client", client.id, "buffer", bufnr)
	gen.attached(client, bufnr)
end

function M.insert_enter(client, bufnr)
    log.trace("Entered insert mode client", client.id, "buffer", bufnr)
	gen.insert_enter(client, bufnr)
end

function M.insert_leave(client, bufnr)
    log.trace("Exited insert mode client", client.id, "buffer", bufnr)
	gen.insert_leave(client, bufnr)
end

return M

