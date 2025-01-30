local log = require('cppgen.log')
local ast = require('cppgen.ast')
local gen = require('cppgen.generator')

---------------------------------------------------------------------------------------------------
-- Generated code validator.
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Local parameters
---------------------------------------------------------------------------------------------------
local L = {
    group     = "CPPGen",
    lspclient = nil,
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
            return have_been_generated(vim.api.nvim_buf_get_lines(bufnr, span.first, span.last+1, false))
        end
    end
    return false
end

--- Calculate Levanshtein distance between two string
local function levenshtein(a, b)
	if a:len() == 0 then return b:len() end
	if b:len() == 0 then return a:len() end

	local matrix = {}
	local a_len = a:len()+1
	local b_len = b:len()+1

	-- increment along the first column of each row
	for i = 1, b_len do
		matrix[i] = {i-1}
	end

	-- increment each column in the first row
	for j = 1, a_len do
		matrix[1][j] = j-1
	end

	-- Fill in the rest of the matrix
	for i = 2, b_len do
		for j = 2, a_len do
			if b:byte(i-1) == a:byte(j-1) then
				matrix[i][j] = matrix[i-1][j-1]
			else
				matrix[i][j] = math.min(
					matrix[i-1][j-1] + 1,	-- substitution
					matrix[i  ][j-1] + 1,	-- insertion
					matrix[i-1][j  ] + 1) 	-- deletion
			end
		end
	end

	return matrix[b_len][a_len]
end

local function same(code, snippet)
    return code == snippet
end

--- Compare actual code against generated snippets and return generated snippet that matches the code
local function match(code, snippets)
    for _,s in ipairs(snippets) do
        if levenshtein(string.sub(code, 1, 100), string.sub(s.insertText, 1, 100)) < 10 then
            return s.insertText
        end
    end
    return nil
end


--- Scan current AST and invoke callback on nodes we think may be interesting
local function visit_relevant_nodes(symbols, bufnr, callback)
    log.trace("Looking for relevant nodes")
    ast.dfs(symbols,
        function(node)
            log.trace("Looking at node", ast.details(node))
            return true
        end,
        function(node)
            if has_been_generated(node, bufnr) then
                local span = ast.span(node)
                if span then
                    gen.visit(symbols, span.first)
                    local code  = table.concat(vim.api.nvim_buf_get_lines(bufnr, span.first, span.last+1, false), '\n')
                    local snip  = match(code, gen.generate())
                    local group = snip and (same(code, snip) and 'CPPGenSignOK' or 'CPPGenSignError') or 'CPPGenSignInfo'
                    vim.fn.sign_place(0, L.group, group, bufnr, { lnum = span.first + 1, priority = 10 })
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
local function validate(bufnr)
	local params = { textDocument = vim.lsp.util.make_text_document_params() }
    -- Should we clear first?
    if L.lspclient then
        vim.fn.sign_unplace(L.group, { buffer = bufnr })
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

--- LSP client attached callback
function M.attached(client, bufnr)
    log.info("Attached client", client.id, "buffer", bufnr)
    L.lspclient = client
    validate(bufnr)
end

--- Entering insert mode.
function M.insert_enter(bufnr)
    log.debug("Entered insert mode buffer:", bufnr)
end

--- Exiting insert mode. Validate new code
function M.insert_leave(bufnr)
    log.debug("Exited insert mode buffer:", bufnr)
end

--- Wrote buffer
function M.after_write(bufnr)
    log.trace("Wrote buffer:", bufnr)
    validate(bufnr)
end


return M

