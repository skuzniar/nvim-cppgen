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
            -- Will be triggered by the first word of the function, but also by this
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
                -- By default we generate conversion from string
                enabled = true
            },
            -- From integer conversion function. Matches enumerator value. Specializations of: template <typename T, typename F> T enum_cast(F f)
            value_cast = {
                -- By default we generate conversion from integers
                enabled = true
            },
            -- Name of the conversion function. Also used as a completion trigger
            name = "enum_cast",
            -- Additional completion trigger if present
            trigger = "cast"
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
            -- Part that will go between case and breqk
            placeholder = function(classname, fieldname)
                return '// ' .. classname .. '::' .. fieldname
            end,
            -- Completion trigger.
            trigger = "case"
        },
    }
}

return M
