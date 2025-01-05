local log = require('cppgen.log')

---------------------------------------------------------------------------------------------------
--- Options module. Provides default configuration options and a mechanism to override them.
---------------------------------------------------------------------------------------------------
local M = {}

---------------------------------------------------------------------------------------------------
--- Default options. Should be merged with user options.
---------------------------------------------------------------------------------------------------
M.merge = function(default, user)
    for k, v in pairs(user) do
        if (type(v) == "table") and (type(default[k] or false) == "table") then
            M.merge(default[k], user[k])
        else
            default[k] = v
        end
    end
    return default
end

---------------------------------------------------------------------------------------------------
--- Default options. Should be merged with user options.
---------------------------------------------------------------------------------------------------
M.default = {
    -- Logging options
    log = {
        plugin      = 'cppgen',
        level       = 'info',
        use_console = false
    },

    -- General options
    disclaimer = '// Auto-generated using cppgen',
    attributes = '[[cppgen::auto]]',
    keepindent = true,

    -- Class type snippet generator
    class = {
        -- Output stream shift operator
        oshift = {
            -- String printed before any fields are printed
            preamble  = function(classname)
                return '[' .. classname .. ']='
            end,
            -- Label part of the field
            label = function(classname, fieldname, camelfield)
                return camelfield .. ': '
            end,
            -- Value part of the field
            value = function(fieldref, type)
                return fieldref
            end,
            separator = "' '"
        }
    },

    -- Enum type snippet generator
    enum = {
        -- Output stream shift operator
        oshift = {
            -- Given an enum mnemonic and optional value, return the corresponding string
            value = function(mnemonic, value)
                if (value) then
                    return '"' .. value .. '(' .. mnemonic .. ')' .. '"'
                else
                    return '"' .. mnemonic .. '"'
                end
            end
        },
        -- Conversion functions
        convert = {
            -- To string conversion function: std::string to_string(enum e)
            to_string = {
                -- Given an enum mnemonic and optional value, return the corresponding string
                value = function(mnemonic, value)
                    if (value) then
                        return '"' .. value .. '(' .. mnemonic .. ')' .. '"'
                    else
                        return '"' .. mnemonic .. '"'
                    end
                end,
                -- We may choose not to generate the function
                enabled = true
            },
        },
    },

    -- JSON serialization using cereal library
    cereal = {
        class = {
            label = function(classname, fieldname, camelized)
                -- demonstrate field skipping
                if camelized == 'SkipMe' then
                    return nil
                end
                return camelized
            end,
            value = function(fieldref, type)
                if type and type == "char" then
                    return 'tv(' .. fieldref .. ')'
                end
                return fieldref
            end,
            xnullcheck = function(fieldref, type)
                return 'isnull(' .. fieldref .. ')'
            end,
            xnullvalue = function(fieldref, type)
                return 'nullptr'
            end
        },
    },

    -- Switch statement generator
    switch = {
        keepindent = false,
        enum = {
            value = function(classname, fieldname)
                return '// ' .. classname .. '::' .. fieldname
            end
        },
    }
}

return M
