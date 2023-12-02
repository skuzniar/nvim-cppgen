local log = require('nvim-cppgen.log')

---------------------------------------------------------------------------------------------------
--- AST utilities
---------------------------------------------------------------------------------------------------
local M = {}

--- AST object returned by LSP server for each buffer
local ast = {}

--- LSP server request callback
local function lsp_callback(bufnr, symbols)
    --log.info(symbols)
	ast[bufnr] = symbols
    log.info("lsp callback - AST array has " .. #ast .. " entries")
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

--- Returns true if the cursor position is within the node's range
local function encloses(node, cursor)
    local line = cursor[1] - 1
    return node.range and node.range['start'].line <= line and node.range['end'].line >= line
end

--- Returns true if the cursor position is past the node's range
local function precedes(node, cursor)
    local line = cursor[1] - 1
    return node.range and node.range['end'].line < line
end

--- Given the cursor position, find smallest enclosing or closest preceding AST node
function M.relevant_node(bufnr, cursor)
    local result = nil
    if ast[bufnr] ~= nil then
        M.dfs(ast[bufnr],
            function(node)
                return node.kind == "TranslationUnit" or node.kind == "CXXRecord" or node.kind == "Enum"
            end,
            function(node)
                if encloses(node, cursor) then
                    --log.info('Found enclosing node ' .. M.name(node))
                    result = node
                end
            end,
            function(node)
                if precedes(node, cursor) and not (result and encloses(result, cursor)) then
                    --log.info('Found preceding node ' .. M.name(node))
                    result = node
                end
            end
        )
    end
    return result
end

--- Make request to LSP server
local awaiting = {}

--- Asynchronous AST request
local function request_ast(client, bufnr)
	if not vim.api.nvim_buf_is_loaded(bufnr) then
        log.info("request_ast: Buffer not loaded " .. bufnr)
		return false
	end
	if awaiting[bufnr] then
        log.info("request_ast: Awaiting response for buffer " .. bufnr)
		return false
	end

    log.info("request_ast: Requesting symbols")
	awaiting[bufnr] = true

	local cur = vim.api.nvim_win_get_cursor(0)
    --log.info(cur)
    local rng = {['start'] = {line = cur[1], character = cur[2]}, ['end'] = {line = cur[1], character = cur[2]}}

    log.info(rng)

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
    --log.info("has_ast " .. bufnr)
    return ast[bufnr] ~= nil
end

--- Clear AST for a given buffer
local function clear_ast(bufnr)
    log.info("clear_ast " .. bufnr)
    ast[bufnr] = nil
end

---------------------------------------------------------------------------------------------------
--- Code generation callbacks
---------------------------------------------------------------------------------------------------
function M.attached(client, bufnr)
    --log.info("attached: " .. tostring(client.id) .. ":" .. tostring(bufnr))

    --- Synchronous timed AST request with client captured
    M.request_ast = function(bufnr, timeout)
        log.info("request_ast: Making synchronous request for AST with timeout " .. tostring(timeout))
        clear_ast(bufnr)
        if not request_ast(client, bufnr) then
            return false
        end
        vim.wait(timeout, function() return has_ast(bufnr) end)
        log.info("request_ast: Returning " .. tostring(has_ast(bufnr)))
        return has_ast(bufnr)
    end
end

function M.insert_enter(client, bufnr)
    log.info("insert_enter: " .. tostring(client.id) .. ":" .. tostring(bufnr))
    request_ast(client, bufnr)
end

function M.insert_leave(client, bufnr)
    log.info("insert_leave: " .. tostring(client.id) .. ":" .. tostring(bufnr))
end

return M
