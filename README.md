# cppgen.nvim

Context-Sensitive Highly Customizable C++ Code Generator for Neovim. This tool is designed to streamline some of the most mundane aspects of the coding process. 

Several Large Language Models (LLMs) can handle a wide range of coding tasks. However, there are reasons why someone might choose to use a custom C++ code generator.
- **Highly Specific Requirements**: Custom generator can be tailored to match a particular coding style.
- **Consistency**: Within a given context, custom generators will always generate the same code. 
- **Customization**: With a custom solution, you have full control over the templates and rules used for code generation.
- **Performance**: A code generator that runs locally is often faster than one that interacts with the remote system.

## Design Philosophy
cppgen acts as a source of code fragments for the completion engine. While in the insert mode, the location of the cursor within the buffer determines the current context. 
Certain language constructs, like classes, enumerations, or switch statements, located above or around the cursor may trigger code generation. cppgen uses type information 
that it gets from the LSP server to generate code.

## Features
cppgen can generate the following code snippets.
- Output stream shift operators for classes and enumerations.
- Serialization functions for classes and enumerations.
- To string conversion functions for enumerations.
- Throwing and non-throwing from string conversion functions for enumerations.
- Throwing and non-throwing from integer conversion functions for enumerations.
- Enumeration switch statements.

## Dependencies
- [nvim-cmp](https://github.com/hrsh7th/nvim-cmp)
- [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig)

## Installation
**Using [lazy.nvim](https://github.com/folke/lazy.nvim):**
```lua
{
    "skuzniar/cppgen.nvim",
    dependencies = {
        "hrsh7th/nvim-cmp",
        "neovim/nvim-lspconfig"
    },
    opts = {}
}
```
For a complete list of options see the [Customization](#customization) section.

## Configuration:

### nvim-cmp:
To link cmp with this source, go into your cmp configuration file and include `{ name = "cppgen" }` under sources.

```lua
cmp.setup {
  ...
  sources = {
    -- cppgen source
    { name = "cppgen" },
    -- other sources
  },
  ...
}
```

# Examples
For a list of examples see [EXAMPLES](EXAMPLES.md)

# Commands
You can type **:CppGenInfo** to see a list of enabled generators and keys that trigger them.

# Customization
Some aspects of code generation can be customized using options. Here are the default options.

```lua
{
    -- Logging options.
    log = {
        -- Name of the log file.
        plugin = 'cppgen',
        -- Log level.
        level = 'info',
        -- Do not print to console.
        use_console = false,
        -- Truncate log file on start.
        truncate = true
    },

    -- Disclaimer comment line placed before the generated code. Set to empty string to disable.
    disclaimer = '// Auto-generated using cppgen',

    -- Generated code can be decorated using an attribute. Set to empty string to disable. Will disable disclaimer.
    attribute = '[[cppgen::auto]]',

    -- Add clang-format on/off guards around parts of generated code.
    keepindent = true,

    -- Class type snippet generator.
    class = {
        -- Output stream shift operator.
        shift = {
            -- String printed before any fields are printed.
            preamble  = function(classname)
                return '[' .. classname .. ']='
            end,
            -- Label part of the field.
            label = function(classname, fieldname, camelized)
                return camelized .. ': '
            end,
            -- Value part of the field.
            value = function(fieldref, type)
                return fieldref
            end,
            -- Separator between fields.
            separator = "' '",
            -- Completion trigger. Will also use the first word of the function definition line.
            trigger = "shift"
        }
    },

    -- Enum type snippet generator.
    enum = {
        -- Output stream shift operator.
        shift = {
            -- Given an enumerator and optional value, return the corresponding string.
            value = function(enumerator, value)
                if (value) then
                    return '"' .. value .. '(' .. enumerator .. ')' .. '"'
                else
                    return '"' .. enumerator .. '"'
                end
            end,
            -- Completion trigger. Will also use the first word of the function definition line.
            trigger = "shift"
        },
        -- To string conversion function: std::string to_string(enum e)
        to_string = {
            -- Given an enumerator and optional value, return the corresponding string.
            value = function(enumerator, value)
                if (value) then
                    return '"' .. value .. '(' .. enumerator .. ')' .. '"'
                else
                    return '"' .. enumerator .. '"'
                end
            end,
            -- Name of the conversion function. Also used as a completion trigger.
            name = "to_string",
            -- Additional completion trigger if present
            trigger = "to_string"
        },
        -- Enum cast functions. Conversions from various types into enum.
        cast = {
            -- From string conversion function. Matches enumerator name. Specializations of: template <typename T, typename F> T enum_cast(F f).
            enum_cast = {
                -- Exception expression thrown if conversion fails
                exception = function(classname, value)
                    return 'std::out_of_range("Value " + std::string(' .. value .. ') + " is outside of ' .. classname .. ' enumeration range.")'
                end,
                -- By default we generate this conversion function.
                enabled = true
            },
            -- No-throw version of enum_cast. Specializations of: template <typename T, typename F, typename E> T enum_cast(F f, E& error).
            enum_cast_no_throw = {
                -- Error type that will be passed from the conversion function.
                errortype = 'std::string',
                -- Error expression returned if conversion fails.
                error = function(classname, value)
                    return '"Value " + std::string(' .. value .. ') + " is outside of ' .. classname .. ' enumeration range."'
                end,
                -- By default we generate this conversion function.
                enabled = true
            },
            -- From integer conversion function. Matches enumerator value. Specializations of: template <typename T, typename F> T enum_cast(F f).
            value_cast = {
                -- Exception expression thrown if conversion fails
                exception = function(classname, value)
                    return 'std::out_of_range("Value " + std::to_string(' .. value .. ') + " is outside of ' .. classname .. ' enumeration range.")'
                end,
                -- By default we generate this conversion function.
                enabled = true
            },
            -- No-throw version of value_cast. Specializations of: template <typename T, typename F, typename E> T enum_cast(F f, E& error).
            value_cast_no_throw = {
                -- Error type that will be passed from the conversion function.
                errortype = 'std::string',
                -- Exception expression thrown if conversion fails.
                error = function(classname, value)
                    return '"Value " + std::to_string(' .. value .. ') + " is outside of ' .. classname .. ' enumeration range."'
                end,
                -- By default we generate this conversion function.
                enabled = true
            },
            -- Name of the conversion function. Also used as a completion trigger.
            name = "enum_cast",
            -- Additional completion trigger if present.
            trigger = "enum_cast"
        },
    },

    -- Serialization using cereal library.
    cereal = {
        -- Class serialization options.
        class = {
            -- Field will be skipped if this function returns nil.
            label = function(classname, fieldname, camelized)
                return camelized
            end,
            value = function(fieldref, type)
                return fieldref
            end,
            -- To disable null check, this function should return nil.
            nullcheck = function(fieldref, type)
                return nil
            end,
            -- If the null check succedes, this is the value that will be serialized. Return nil to skip the serialization.
            nullvalue = function(fieldref, type)
                return 'nullptr'
            end,
            -- Name of the conversion function. Also used as a completion trigger.
            name = "save",
            -- Additional completion trigger if present.
            trigger = "json"
        },
    },

    -- Switch statement generator.
    switch = {
        -- Switch on enums.
        enum = {
            -- Part that will go between case and break.
            placeholder = function(classname, value)
                return '// ' .. classname .. '::' .. value
            end,
            --  Expression for the default case. If nil, no default case will be generated.
            default = function(classname, value)
                return '// "Value " + std::to_string(' .. value .. ') + " is outside of ' .. classname .. ' enumeration range."'
            end,
            -- Completion trigger..
            trigger = "case"
        },
    }
}
```

