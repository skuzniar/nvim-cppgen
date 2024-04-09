local log = require('nvim-cppgen.log')

---------------------------------------------------------------------------------------------------
--- AST utilities
---------------------------------------------------------------------------------------------------
local M = {}

--- AST object returned by LSP server for each buffer
local ast = {}

--- LSP server request callback
local function lsp_callback(bufnr, symbols)
    log.info("Received AST data with", (symbols and symbols.children and #symbols.children or 0), "top level nodes")
    log.trace(symbols)
	ast[bufnr] = symbols
end

--- Return node details - name and range, adjusted for line numbers starting from one.
function M.details(node)
    if node then
        if node.range then
            return node.role .. ' ' .. node.kind .. ' ' .. (node.detail or "<???>") .. '[' .. node.range['start'].line .. ',' .. node.range['end'].line .. ']'
        else
            return node.role .. ' ' .. node.kind .. ' ' .. (node.detail or "<???>") .. '[]'
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

--- Depth first traversal over AST tree with descend filter, pre and post order operations.
function M.dfs(node, filt, pref, posf)
    pref(node)
    if filt(node) then
        if node.children then
            for _, child in ipairs(node.children) do
	            M.dfs(child, filt, pref, posf)
		    end
	    end
    end
    if posf then
        posf(node)
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
function M.encloses(node, line)
    return not node.range or node.range['start'].line < line and node.range['end'].line > line
end

--- Returns true if the cursor line position is past the node's range
function M.precedes(node, line)
    return node.range ~= nil and node.range['end'].line < line
end

--- Returns true if two nodes perfectly overlay each other
function M.overlay(nodea, nodeb)
    return nodea and nodeb and nodea.range and nodeb.range and nodea.range['end'].line == nodeb.range['end'].line and nodea.range['start'].line == nodeb.range['start'].line
end

--- Returns true if the node has zero range
function M.phantom(node)
    return node.range ~= nil and node.range['end'].line == node.range['start'].line
end

--- Scan AST and invoke callback on nodes we think may be interesting
function M.visit_relevant_nodes(bufnr, line, callback)
    log.debug("Looking for relevant nodes in buffer", bufnr, "at line", line)

    if ast[bufnr] == nil then
        return false
    end

    M.dfs(ast[bufnr],
        function(node)
            log.debug("Looking at node", M.details(node), "phantom=", M.phantom(node), "encloses=", M.encloses(node, line))
            return M.encloses(node, line)
        end,
        function(node)
            if M.encloses(node, line) then
                log.debug("Found enclosing node", M.details(node))
                callback(node, line)
            end
        end,
        function(node)
            if M.precedes(node, line) then
                log.debug("Found preceding node", M.details(node))
                callback(node, line)
            end
        end
    )

    return true
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

    ast[bufnr] = nil
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

---------------------------------------------------------------------------------------------------
--- Code generation callbacks
---------------------------------------------------------------------------------------------------
function M.attached(client, bufnr)
    log.trace("Attached client", client.id, "buffer", bufnr)
end

function M.insert_enter(client, bufnr)
    log.trace("Entered insert mode client", client.id, "buffer", bufnr)
    request_ast(client, bufnr)
end

function M.insert_leave(client, bufnr)
    log.trace("Exited insert mode client", client.id, "buffer", bufnr)
end

return M
