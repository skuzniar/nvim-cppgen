local log = require('nvim-cppgen.log')

---------------------------------------------------------------------------------------------------
--- AST utilities
---------------------------------------------------------------------------------------------------
local M = {}

--- AST object returned by LSP server for each buffer
local ast = {}

--- Relevant nodes cache for the current buffer
local relnodes = {}

--- LSP server request callback
local function lsp_callback(bufnr, symbols)
    log.info("Received AST data with", (symbols and symbols.children and #symbols.children or 0), "top level nodes")
    log.trace(symbols)
	ast[bufnr] = symbols
    relnodes[bufnr] = nil
end

--- Return node details - name and range, adjusted for line numbers starting from one.
function M.details(node)
    if node then
        if node.range then
            return node.kind .. ' ' .. (node.detail or "<???>") .. '[' .. node.range['start'].line .. ',' .. node.range['end'].line .. ']'
        else
            return node.kind .. ' ' .. (node.detail or "<???>") .. '[]'
        end
    else
        return 'nil'
    end
end

--- Return node name.
function M.name(node)
    if node then
        return (node.detail or "<???>")
    else
        return 'nil'
    end
end

--- Depth first traversal over AST tree with filter, pre and post order operations.
function M.dfs(node, filt, pref, posf)
    if filt(node) then
        pref(node)
        if node.children then
            for _, child in ipairs(node.children) do
	            M.dfs(child, filt, pref, posf)
		    end
	    end
        if posf then
            posf(node)
        end
    end
end

--- Visit immediate children of a given node.
function M.visit_children(node, f)
    if node.children then
        for _, child in ipairs(node.children) do
            f(child)
		end
    end
end

--- Count immediate children of a given node that satisfy the predicate.
function M.count_children(node, p)
    local cnt = 0
    if node.children then
        for _, child in ipairs(node.children) do
            if p(child) then
               cnt = cnt + 1
            end
		end
    end
    return cnt
end

--- Returns true if the cursor line position is within the node's range
local function encloses(node, line)
    return node.range and node.range['start'].line < line and node.range['end'].line > line
end

--- Returns true if the cursor line position is past the node's range
local function precedes(node, line)
    return node.range and node.range['end'].line < line
end

--- Returns true if the node is implicit - has zero range
local function phantom(node)
    return node.range and node.range['end'].line == node.range['start'].line
end

--- Given the line cursor position, find smallest enclosing and closest preceding AST node
function M.relevant_nodes(bufnr, line)
    if relnodes[bufnr] then
        return relnodes[bufnr]
    end

    log.debug("Looking for relevant nodes in buffer", bufnr, "at line", line)

    local result = {}
    if ast[bufnr] ~= nil then
        M.dfs(ast[bufnr],
            function(node)
                log.trace("Looking at node", M.details(node))
                return not phantom(node)
            end,
            function(node)
                if encloses(node, line) then
                    log.trace("Found enclosing node", M.details(node))
                    result.enclosing = node
                end
            end,
            function(node)
                if precedes(node, line) then
                    log.trace("Found preceding node", M.details(node))
                    result.preceding = node
                end
            end
        )
    end

    relnodes[bufnr] = result

    log.debug("Preceding =", (result.preceding and M.details(result.preceding) or result.preceding),
              "Enclosing =", (result.enclosing and M.details(result.enclosing) or result.enclosing))
    return result
end

--- Make request to LSP server
local awaiting = {}

--- Asynchronous AST request
local function request_ast(client, bufnr)
	if not vim.api.nvim_buf_is_loaded(bufnr) then
        log.debug("Buffer not loaded", bufnr)
		return false
	end
	if awaiting[bufnr] then
        log.debug("Awaiting response for buffer", bufnr)
		return false
	end

	awaiting[bufnr] = true

    log.info("Requesting AST data for buffer", bufnr)
    -- TODO - debug range parameter
	--client.request("textDocument/ast", { textDocument = vim.lsp.util.make_text_document_params(), xrange = rng}, function(err, symbols, _)
	client.request("textDocument/ast", { textDocument = vim.lsp.util.make_text_document_params()}, function(err, symbols, _)
	    awaiting[bufnr] = false
		if vim.api.nvim_buf_is_valid(bufnr) then
		    if err ~= nil then
                log.error(err)
            else
				lsp_callback(bufnr, symbols or {})
			end
		end
	end , bufnr)
    return true
end

--- Check if AST is present for a given buffer
local function has_ast(bufnr)
    log.trace("has_ast: bufnr=", bufnr)
    return ast[bufnr] ~= nil
end

--- Clear AST for a given buffer
local function clear_ast(bufnr)
    log.trace("clear_ast: bufnr =", bufnr)
    ast[bufnr] = nil
end

---------------------------------------------------------------------------------------------------
--- Code generation callbacks
---------------------------------------------------------------------------------------------------
function M.attached(client, bufnr)
    log.trace("Attached client", client.id, "buffer", bufnr)
end

function M.insert_enter(client, bufnr)
    log.trace("Entered insert mode in buffer", bufnr)
    relnodes[bufnr] = nil
    request_ast(client, bufnr)
end

function M.insert_leave(client, bufnr)
    log.trace("Exited insert mode in buffer", bufnr)
end

return M
