local log = require('cppgen.log')
local ast = require('cppgen.ast')
local ctx = require('cppgen.context')

---------------------------------------------------------------------------------------------------
-- Completion code snippet generator. Implements code completion source interface. Uses a
-- collection of specilized generators to produce code snippets.
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Local parameters
---------------------------------------------------------------------------------------------------
local L = {
    disclaimer = '',
    lspclient  = nil
}

---------------------------------------------------------------------------------------------------
-- Global parameters for code generation.
-- TODO - populate during configuration
---------------------------------------------------------------------------------------------------
local G = {
    require('cppgen.generators.class'),
    require('cppgen.generators.enum'),
    require('cppgen.generators.cereal'),
    require('cppgen.generators.switch')
}

--- Exported functions
local M = {}

--- Scan current AST, find immediately preceding and closest enclosing nodes and invoke callback on them.
local function visit_relevant_nodes(symbols, line, callback)
    log.trace("Looking for relevant nodes at line", line)

    local preceding = nil
    local enclosing = nil

    ast.dfs(symbols,
        function(node)
            log.debug("Looking at node", ast.details(node), "phantom=", ast.phantom(node), "encloses=", ast.encloses(node, line))
            return ast.encloses(node, line)
        end,
        function(node)
            if ast.encloses(node, line) and not ast.overlay(enclosing, node) then
                enclosing = node
                log.debug("Found enclosing node", ast.details(node))
                log.trace(node)
            end
        end,
        function(node)
            if ast.precedes(node, line) and not ast.overlay(preceding, node) then
                preceding = node
                log.debug("Found preceding node", ast.details(node))
                log.trace(node)
            end
        end
    )
    -- TODO - handle 'TypeAlias' nodes
    if preceding then
        log.debug("Selected preceding node", ast.details(preceding))
        callback(preceding, ast.Precedes)
    end
    if enclosing then
        log.debug("Selected enclosing node", ast.details(enclosing))
        callback(enclosing, ast.Encloses)
    end
end

--- Visit AST nodes
local function visit(symbols, bufnr)
    log.trace("visit:", "buffer", bufnr)

    -- We may have left insert mode by the time AST arrived
	local cursor = ctx.context(bufnr)
    if cursor ~= nil then
	    local line = ctx.context(bufnr)[1] - 1
        visit_relevant_nodes(symbols, line,
            function(node, location)
                for _,g in pairs(G) do
                    g.visit(node, location)
                end
            end
        )
    end
end

--- Return true if th code can be generated in the current context - buffer and cursor position
local function available(bufnr)
    log.trace("available:", "buffer", bufnr)
    local result = false
    for _,g in pairs(G) do
        result = result or g.available()
    end
    log.debug("Can" .. (result and " " or " not ") .. "generate code in buffer", bufnr)
    return result
end

--- Generate code completion items appropriate for the current context
local function generate(bufnr)
	local cursor = ctx.context(bufnr)
    if cursor then
        log.info("Generating code in buffer", bufnr)
        local total = {}
        for _,g in pairs(G) do
            local items = g.generate();
            for _,i in ipairs(items) do
                table.insert(total, i)
            end
        end
        log.info("Collected", #total, "completion items")
        return total
    end
end

---------------------------------------------------------------------------------------------------
-- Start of code completion source interface.
---------------------------------------------------------------------------------------------------

--- Return new source
function M:source()
    log.trace('source')
    return setmetatable({}, { __index = M })
end

---------------------------------------------------------------------------------------------------
--- Return whether this source is available in the current context or not (optional).
---------------------------------------------------------------------------------------------------
function M:is_available()
    log.trace('is_available')
    return available(vim.api.nvim_get_current_buf())
end

---------------------------------------------------------------------------------------------------
--- Return the debug name of this source (optional).
---------------------------------------------------------------------------------------------------
--[[
function M:get_debug_name()
    log.trace('get_debug_name')
    return 'c++gen'
end
]]

---------------------------------------------------------------------------------------------------
--- Return LSP's PositionEncodingKind (optional).
---------------------------------------------------------------------------------------------------
--[[
function M:get_position_encoding_kind()
    log.trace('get_position_encoding_kind')
  return 'utf-16'
end
]]

---------------------------------------------------------------------------------------------------
--- Return the keyword pattern for triggering completion (optional).
---------------------------------------------------------------------------------------------------
--[[
function M:get_keyword_pattern()
    log.trace('get_keyword_pattern')
    return 'friend'
end
]]

---------------------------------------------------------------------------------------------------
--- Return trigger characters for triggering completion (optional).
---------------------------------------------------------------------------------------------------
--[[
function M:get_trigger_characters()
    log.trace('get_trigger_characters')
    return { '.' }
end
]]

---------------------------------------------------------------------------------------------------
--- Invoke completion (required).
---------------------------------------------------------------------------------------------------
function M:complete(params, callback)
    log.trace('complete:', params)
    local items = generate(params.context.bufnr)
    if items then
        callback(items)
    end
end

---------------------------------------------------------------------------------------------------
--- Resolve completion item (optional). This is called right before the completion is about to be displayed.
---------------------------------------------------------------------------------------------------
function M:resolve(completion_item, callback)
    log.trace('resolve:', completion_item)
    if L.disclaimer and string.len(L.disclaimer) > 0 then
        completion_item.insertText = L.disclaimer .. '\n' .. completion_item.insertText
    end
    callback(completion_item)
end

---------------------------------------------------------------------------------------------------
--- Executed after the item was selected.
---------------------------------------------------------------------------------------------------
--[[
function M:execute(completion_item, callback)
    log.trace('execute')
    callback(completion_item)
end
]]

---------------------------------------------------------------------------------------------------
-- End of code completion source interface.
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
--- Initialization and lifecycle callbacks
---------------------------------------------------------------------------------------------------

--- Initialization callback
function M.setup(opts)
    L.disclaimer = opts.disclaimer or ''

    for _,g in pairs(G) do
        g.setup(opts)
    end
end

--- LSP client attached callback
function M.attached(client, bufnr)
    log.trace("Attached client", client.id, "buffer", bufnr)
    L.lspclient = client
    for _,g in pairs(G) do
        if g.attached then
            g.attached(client, bufnr)
        end
    end
end

--- Entering insert mode. Reset generators and request AST data. Upon completion visit AST nodes.
function M.insert_enter(client, bufnr)
    log.trace("Entered insert mode client", client.id, "buffer", bufnr)

    for _,g in pairs(G) do
        g.reset()
    end

	local params = { textDocument = vim.lsp.util.make_text_document_params() }
    if L.lspclient then
        log.trace("requesting ", client.id, "buffer", bufnr)
	    L.lspclient.request("textDocument/ast", params, function(err, symbols, _)
            if err ~= nil then
                log.error(err)
            else
                log.info("Received AST data with", (symbols and symbols.children and #symbols.children or 0), "top level nodes")
                log.trace(symbols)
                visit(symbols, bufnr)
		    end
	    end)
    end
end

--- Exiting insert mode.
function M.insert_leave(client, bufnr)
    log.trace("Exited insert mode client", client.id, "buffer", bufnr)
end

--- Info callback
function M.info()
    local total = {}
    for _,g in pairs(G) do
        local items = g.info();
        for _,i in ipairs(items) do
            table.insert(total, i)
        end
    end
    table.sort(total, function(a, b) return a[1] < b[1] end)
    return total
end

return M

