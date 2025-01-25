local log = require('cppgen.log')
local ast = require('cppgen.ast')
local ctx = require('cppgen.context')

---------------------------------------------------------------------------------------------------
-- Generated code validator.
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Local parameters
---------------------------------------------------------------------------------------------------
local L = {
    group = "CPPGen",
}

---------------------------------------------------------------------------------------------------
-- Global parameters for code generation.
-- TODO - get them from generator
---------------------------------------------------------------------------------------------------
local G = {
    require('cppgen.generators.class'),
    require('cppgen.generators.enum'),
    require('cppgen.generators.cereal'),
    require('cppgen.generators.switch')
}

--- Exported functions
local M = {}

--- Check if the lines of code have been generated
local function have_been_generated(lines)
    for _,l in ipairs(lines) do
        if string.match(l, L.attribute) then
            return true
        end
    end
    return false
end

--- Check if the code represented by a node in a given buffer has been generated
local function has_been_generated(node, bufnr)
    if node.kind == 'FunctionXroto' or node.kind == 'Function' then
        local span = ast.span(node)
        if span then
            return have_been_generated(vim.api.nvim_buf_get_lines(bufnr, span.first, span.last, false))
        end
    end
    return false
end

--- Scan current AST and invoke callback on nodes we think may be interesting
local function visit_relevant_nodes(symbols, bufnr, callback)
    log.debug("Looking for relevant nodes")
    ast.dfs(symbols,
        function(node)
            log.debug("Looking at node", ast.details(node))
            return true
        end,
        function(node)
            if has_been_generated(node, bufnr) then
                local span = ast.span(node)
                if span then
                    --vim.fn.sign_place(0, L.group, 'CPPGenSignOK', bufnr, { lnum = span.first + 1, priority = 10 })
                end
                callback(node)
            end
        end
    )
end

--- Visit AST nodes
local function visit(symbols, bufnr)
    log.trace("visit:", "buffer", bufnr)
    visit_relevant_nodes(symbols, bufnr,
        function(node)
            for _,g in pairs(G) do
                g.validate(node)
            end
        end
    )
end

---------------------------------------------------------------------------------------------------
--- Initialization and lifecycle callbacks
---------------------------------------------------------------------------------------------------

--- Initialization callback
function M.setup(opts)
    L.attribute = opts.attribute

    -- Configure diagnostics
    local signs = {
        -- Ctl-V ue646
        { name = "CPPGenSignError", text = "", texthl = "DiagnosticSignError" },
        { name = "CPPGenSignWarn",  text = "", texthl = "DiagnosticSignWarn" },
        { name = "CPPGenSignInfo",  text = "", texthl = "DiagnosticSignInfo" },
        { name = "CPPGenSignOK",    text = "", texthl = "DiagnosticSignOK" },
    }

    for _, sign in ipairs(signs) do
        vim.fn.sign_define(sign.name, { texthl = sign.texthl, text = sign.text, numhl = "" })
    end
end

--- Validate generated code in the buffer
local function validate(client, bufnr)
	local params = { textDocument = vim.lsp.util.make_text_document_params() }
    -- Should we clear first?
    vim.fn.sign_unplace(L.group, { buffer = bufnr })
	client.request("textDocument/ast", params, function(err, symbols, _)
        if err ~= nil then
            log.error(err)
        else
            log.info("Received AST data with", (symbols and symbols.children and #symbols.children or 0), "top level nodes")
            log.trace(symbols)
            visit(symbols, bufnr)
        end
	end)
end

--- LSP client attached callback
function M.attached(client, bufnr)
    log.info("Attached client", client.id, "buffer", bufnr)
    validate(client, bufnr)
end

--- Entering insert mode.
function M.insert_enter(client, bufnr)
    log.trace("Entered insert mode client", client.id, "buffer", bufnr)
end

--- Exiting insert mode. Validate new code
function M.insert_leave(client, bufnr)
    log.trace("Exited insert mode client", client.id, "buffer", bufnr)
    validate(client, bufnr)
end

return M

