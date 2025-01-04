# cppgen.nvim
Neovim C++ code snippets generator.

## Install

```lua
{
    "skuzniar/cppgen.nvim",
    dependencies = {
        "neovim/nvim-lspconfig"
    },
    opts =
    {
        log = {
            plugin      = 'cppgen',
            level       = 'debug',
            use_console = false
        },

        keepindent = true,

        -- Generators for Class type
        class = {
            separator = "' '",
            preamble  = function(classname)
                return '[' .. classname .. ']='
            end,
            label = function(classname, fieldname, camelized)
                return camelized .. ': '
            end,
            value = function(fieldref, type)
                return fieldref
            end
        },

        -- Generators for Enum type
        enum = {
            value = function(mnemonic, value)
                if (value) then
                    return '"' .. value .. ' (' .. mnemonic .. ')' .. '"'
                else
                    return '"' .. mnemonic .. '"'
                end
            end
        },

        -- JSON serialization using cereal library
        cereal = {
            class = {
                label = function(classname, fieldname, camelized)
                    return camelized
                end,
                value = function(fieldref, type)
                    return fieldref
                end
            },
        }

        -- Switch statement generator for enum types
        switch = {
            keepindent = false,
            enum = {
                value = function(classname, fieldname)
                    return '// ' .. classname .. '::' .. fieldname
                end
            },
        }
    }
}
```

