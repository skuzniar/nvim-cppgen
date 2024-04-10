local ast = require('nvim-cppgen.ast')
local ctx = require('nvim-cppgen.ctx')
local log = require('nvim-cppgen.log')

---------------------------------------------------------------------------------------------------
-- 1. Collection of code generators. Gathers code completion items from specialized generators.
-- 2. Reacts to editor mode changes to cache results.
---------------------------------------------------------------------------------------------------

-- TODO - populate during configuration
local G = {
    require('nvim-cppgen.gen.oss'),
    require('nvim-cppgen.gen.cnv'),
    require('nvim-cppgen.gen.cereal'),
    require('nvim-cppgen.gen.switch')
}

--- Reset code generators
local function reset()
    for _,g in pairs(G) do
        g.reset()
    end
end

--- Scan current AST and invoke callback on nodes we think may be interesting
local function visit_relevant_nodes(symbols, line, callback)
    log.debug("Looking for relevant nodes at line", line)

    ast.dfs(symbols,
        function(node)
            log.debug("Looking at node", ast.details(node), "phantom=", ast.phantom(node), "encloses=", ast.encloses(node, line))
            return ast.encloses(node, line)
        end,
        function(node)
            if ast.encloses(node, line) then
                log.debug("Found enclosing node", ast.details(node))
                callback(node, line)
            end
        end,
        function(node)
            if ast.precedes(node, line) then
                log.debug("Found preceding node", ast.details(node))
                callback(node, line)
            end
        end
    )
end

--- Visit AST nodes
local function visit(symbols, bufnr)
    log.trace("visit:", "buffer", bufnr)

	local line = ctx.context(bufnr)[1] - 1
    visit_relevant_nodes(symbols, line,
        function(n, l)
            for _,g in pairs(G) do
                g.visit(n, l)
            end
        end
    )
end

--- Exported functions
local M = {}

--- Return true if th code can be generated in the current context - buffer and cursor position
function M.available(bufnr)
    log.trace("available:", "buffer", bufnr)
    local result = false
    for _,g in pairs(G) do
        result = result or g.available()
    end
    log.debug("Can" .. (result and " " or " not ") .. "generate code in buffer", bufnr)
    return result
end

--- Generate code completion items appropriate for the current context
function M.generate(bufnr)
	local cursor = ctx.context(bufnr)
    if cursor then
        log.info("Generating code in buffer", bufnr)
        local total = {}
        for _,g in pairs(G) do
            local items = g.completion_items();
            for _,i in ipairs(items) do
                table.insert(total, i)
            end
        end
        log.info("Collected", #total, "completion items")
        return total
    end
end

---------------------------------------------------------------------------------------------------
--- Initialization callback
---------------------------------------------------------------------------------------------------
function M.setup(opts)
    -- Pass the configuration to the snippet generators
    for _,g in pairs(G) do
        g.setup(opts)
    end
end

---------------------------------------------------------------------------------------------------
--- Code generation callbacks
---------------------------------------------------------------------------------------------------
local lspclient = nil

function M.attached(client, bufnr)
    log.trace("Attached client", client.id, "buffer", bufnr)
    lspclient = client
    for _,g in pairs(G) do
        if g.attached then
            g.attached(client, bufnr)
        end
    end
end

function M.insert_enter(client, bufnr)
    log.trace("Entered insert mode client", client.id, "buffer", bufnr)

    reset()

	local params = { textDocument = vim.lsp.util.make_text_document_params() }
    if lspclient then
        log.trace("requesting ", client.id, "buffer", bufnr)
	    lspclient.request("textDocument/ast", params, function(err, symbols, _)
            if err ~= nil then
                log.error(err)
            else
                log.info("Received AST data with", (symbols and symbols.children and #symbols.children or 0), "top level nodes")
                --log.trace(symbols)
                visit(symbols, bufnr)
		    end
	    end)
    end
end

function M.insert_leave(client, bufnr)
    log.trace("Exited insert mode client", client.id, "buffer", bufnr)
end

return M
