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

    -- Disclaimer and attributes. Set to empty string to disable
    disclaimer = '// Auto-generated using cppgen',
    attributes = '[[cppgen::auto]]',

    -- Add clang-format on/off guards around parts of generated code
    keepindent = true,

    -- Class type snippet generator
    class = {
        -- Output stream shift operator
        shift = {
            -- String printed before any fields are printed
            preamble  = function(classname)
                return '[' .. classname .. ']='
            end,
            -- Label part of the field
            label = function(classname, fieldname, camelized)
                return camelized .. ': '
            end,
            -- Value part of the field
            value = function(fieldref, type)
                return fieldref
            end,
            -- Separator between fields
            separator = "' '",
            -- Completion trigger. Will also use the first word of the function definition line
            trigger = "shift"
        }
    },

    -- Enum type snippet generator
    enum = {
        -- Output stream shift operator
        shift = {
            -- Given an enumerator and optional value, return the corresponding string
            value = function(enumerator, value)
                if (value) then
                    return '"' .. value .. '(' .. enumerator .. ')' .. '"'
                else
                    return '"' .. enumerator .. '"'
                end
            end,
            -- Completion trigger. Will also use the first word of the function definition line
            trigger = "shift"
        },
        -- To string conversion function: std::string to_string(enum e)
        to_string = {
            -- Given an enumerator and optional value, return the corresponding string
            value = function(enumerator, value)
                if (value) then
                    return '"' .. value .. '(' .. enumerator .. ')' .. '"'
                else
                    return '"' .. enumerator .. '"'
                end
            end,
            -- Name of the conversion function. Also used as a completion trigger
            name = "to_string",
            -- Additional completion trigger if present
            trigger = "to_string"
        },
        -- Enum cast functions. Conversions from various types into enum
        cast = {
            -- From string conversion function. Matches enumerator name. Specializations of: template <typename T, typename F> T enum_cast(F f)
            enum_cast = {
                -- Exception expression thrown if conversion fails
                exception = function(classname, value)
                    return 'std::out_of_range("Value " + std::string(' .. value .. ') + " is outside of ' .. classname .. ' enumeration range.")'
                end,
                -- By default we generate this conversion function
                enabled = true
            },
            -- No-throw version of enum_cast. Specializations of: template <typename T, typename F, typename E> T enum_cast(F f, E& error)
            enum_cast_no_throw = {
                -- Error type that will be passed from the conversion function
                errortype = 'std::string',
                -- Error expression returned if conversion fails
                error = function(classname, value)
                    return '"Value " + std::string(' .. value .. ') + " is outside of ' .. classname .. ' enumeration range."'
                end,
                -- By default we generate this conversion function
                enabled = true
            },
            -- From integer conversion function. Matches enumerator value. Specializations of: template <typename T, typename F> T enum_cast(F f)
            value_cast = {
                -- Exception expression thrown if conversion fails
                exception = function(classname, value)
                    return 'std::out_of_range("Value " + std::to_string(' .. value .. ') + " is outside of ' .. classname .. ' enumeration range.")'
                end,
                -- By default we generate this conversion function
                enabled = true
            },
            -- No-throw version of value_cast. Specializations of: template <typename T, typename F, typename E> T enum_cast(F f, E& error)
            value_cast_no_throw = {
                -- Error type that will be passed from the conversion function
                errortype = 'std::string',
                -- Exception expression thrown if conversion fails
                error = function(classname, value)
                    return '"Value " + std::to_string(' .. value .. ') + " is outside of ' .. classname .. ' enumeration range."'
                end,
                -- By default we generate this conversion function
                enabled = true
            },
            -- Name of the conversion function. Also used as a completion trigger
            name = "enum_cast",
            -- Additional completion trigger if present
            trigger = "enum_cast"
        },
    },

    -- JSON serialization using cereal library
    cereal = {
        -- Class serialization options
        class = {
            -- Field will be skipped if this function returns nil
            label = function(classname, fieldname, camelized)
                return camelized
            end,
            value = function(fieldref, type)
                return fieldref
            end,
            -- To disable null check, this function should return nil
            nullcheck = function(fieldref, type)
                return nil
            end,
            -- If the null check succedes, this is the value that will be serialized. Return nil to skip the serialization
            nullvalue = function(fieldref, type)
                return 'nullptr'
            end,
            -- Name of the conversion function. Also used as a completion trigger
            name = "save",
            -- Additional completion trigger if present
            trigger = "json"
        },
    },

    -- Switch statement generator
    switch = {
        -- Switch on enums
        enum = {
            -- Part that will go between case and break
            placeholder = function(classname, value)
                return '// ' .. classname .. '::' .. value
            end,
            --  Expression for the default case. If nil, no default case will be generated
            default = function(classname, value)
                return '// "Value " + std::to_string(' .. value .. ') + " is outside of ' .. classname .. ' enumeration range."'
            end,
            -- Completion trigger.
            trigger = "case"
        },
    }
}

return M
