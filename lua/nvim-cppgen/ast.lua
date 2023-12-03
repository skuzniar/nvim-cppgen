local log = require('nvim-cppgen.log')

---------------------------------------------------------------------------------------------------
--- AST utilities
---------------------------------------------------------------------------------------------------
local M = {}

--- AST object returned by LSP server for each buffer
local ast = {}

--- LSP server request callback
local function lsp_callback(bufnr, symbols)
    log.info("lsp_callback: Received AST data with", (symbols and symbols.children and #symbols.children or 0), "top level nodes")
	ast[bufnr] = symbols
end

--- Return node details - name and range, adjusted for line numbers starting from one.
function M.details(node)
    return node.kind .. ' ' .. (node.detail or "<???>") .. '[' .. node.range['start'].line + 1 .. ',' .. node.range['end'].line + 1 .. ']'
end

--- Return node name.
function M.name(node)
    return (node.detail or "<???>")
end

--- Depth first traversal over AST tree with filter, pre and post order operations.
function M.dfs(node, filt, pref, posf)
    pref(node)
    if node.children then
        for _, child in ipairs(node.children) do
            if filt(child) then
	            M.dfs(child, filt, pref, posf)
		    end
		end
	end
    if posf then
        posf(node)
    end
end

--- Returns true if the cursor line position is within the node's range
local function encloses(node, line)
    log.trace("encloses")
    return node.range and node.range['start'].line <= line and node.range['end'].line >= line
end

--- Returns true if the cursor line position is past the node's range
local function precedes(node, line)
    log.trace("precedes")
    return node.range and node.range['end'].line < line
end

--- Returns true if the cursor line position is before the node's range
local function follows(node, line)
    log.trace("follows")
    return node.range and node.range['start'].line > line
end

--- Relevant node for the current buffer
local relnode = {}

--- Given the cursor position, find smallest enclosing or closest preceding AST node
function M.relevant_node(bufnr, cursor)
    log.debug("relevant_node: Looking for relevant node in buffer", bufnr)
    if relnode[bufnr] then
        log.debug("relevant_node: Found relevant node in the cache", M.details(relnode[bufnr]))
        return relnode[bufnr]
    end

    local line = cursor[1] - 1

    local result = nil
    if ast[bufnr] ~= nil then
        M.dfs(ast[bufnr],
            function(node)
                log.debug('relevant_node: Looking at node', M.details(node))
                return not follows(node, line) and (node.kind == "TranslationUnit" or node.kind == "CXXRecord" or node.kind == "Enum")
            end,
            function(node)
                if encloses(node, line) then
                    log.debug('relevant_node: Found enclosing node ' .. M.name(node))
                    result = node
                end
            end,
            function(node)
                if precedes(node, line) and not (result and encloses(result, line)) then
                    log.debug('relevant_node: Found preceding node ' .. M.name(node))
                    result = node
                end
            end
        )
    end

    if result then
        log.debug("relevant_node: Found relevant node", M.details(result))
        relnode[bufnr] = result
    end
    return result
end

--- Make request to LSP server
local awaiting = {}

--- Asynchronous AST request
local function request_ast(client, bufnr)
	if not vim.api.nvim_buf_is_loaded(bufnr) then
        log.debug("request_ast: Buffer not loaded " .. bufnr)
		return false
	end
	if awaiting[bufnr] then
        log.debug("request_ast: Awaiting response for buffer " .. bufnr)
		return false
	end

	awaiting[bufnr] = true

	local cur = vim.api.nvim_win_get_cursor(0)
    local rng = {['start'] = {line = cur[1], character = cur[2]}, ['end'] = {line = cur[1], character = cur[2]}}
    log.debug("request_ast: cursor=", cur, " range=", rng)

    log.info("request_ast: Requesting AST data")
    -- TODO - debug range parameter
	client.request("textDocument/ast", { textDocument = vim.lsp.util.make_text_document_params(), xrange = rng}, function(err, symbols, _)
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
    log.trace("clear_ast: bufnr=", bufnr)
    ast[bufnr] = nil
end

---------------------------------------------------------------------------------------------------
--- Code generation callbacks
---------------------------------------------------------------------------------------------------
function M.attached(client, bufnr)
    log.trace("attached:", client.id, ':', bufnr)

    --- Synchronous timed AST request with client captured
    M.request_ast = function(bufnr, timeout)
        log.debug("request_ast: Making synchronous request for AST with timeout=", timeout)
        clear_ast(bufnr)
        if not request_ast(client, bufnr) then
            return false
        end
        vim.wait(timeout, function() return has_ast(bufnr) end)
        log.debug("request_ast: Returning success=", has_ast(bufnr))
        return has_ast(bufnr)
    end
end

function M.insert_enter(client, bufnr)
    log.trace("insert_enter:", client.id, ':', bufnr)
    relnode[bufnr] = nil
    request_ast(client, bufnr)
end

function M.insert_leave(client, bufnr)
    relnode[bufnr] = nil
    log.trace("insert_leave:", client.id, ':', bufnr)
end

return M
