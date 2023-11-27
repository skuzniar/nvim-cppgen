local cgn = require("nvim-cppgen.cgn")
local log = require('nvim-cppgen.log')

local M = {}

--- LSP attach callback
local function attach(client, bufnr)
    log.info("attach: " .. tostring(client.id) .. ":" .. tostring(bufnr))

    -- Inform code generator that LPS client has been attached to the buffer
	cgn.attached(client, bufnr)

	local group = vim.api.nvim_create_augroup("cppgen", { clear = false })

	vim.api.nvim_clear_autocmds({
		group  = group,
		buffer = bufnr
	})

	vim.api.nvim_create_autocmd({ "InsertEnter" }, {
		callback = function(args)
			cgn.insert_enter(client, bufnr)
		end,
		group  = group,
		buffer = bufnr
	})
	vim.api.nvim_create_autocmd({ "InsertLeave" }, {
		callback = function(args)
			cgn.insert_leave(client, bufnr)
		end,
		group  = group,
		buffer = bufnr
	})

end

--- Setup
function M.setup(opts)
    -- Parse options - TODO
    log.info("setup")
	if opts ~= nil then
	    if opts.xyz ~= nil then
		    config.xyz = opts.xyz
	    end
	end

	vim.api.nvim_create_autocmd("LspAttach", {
		callback = function(args)
            if vim.bo.filetype == "cpp" then
			    local client = vim.lsp.get_client_by_id(args.data.client_id)
	            if client.server_capabilities.astProvider then
                    log.info("LSP server is capable of delivering AST data.")
				    attach(client, args.buf)
			    end
			end
		end,
	})

    -- Add our source to cmp
    require('cmp').register_source('cppgen', cgn.source())
end

return M
