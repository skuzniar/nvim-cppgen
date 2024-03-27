local ast = require('nvim-cppgen.ast')
local log = require('nvim-cppgen.log')

local cmp = require('cmp')

---------------------------------------------------------------------------------------------------
-- Conversion function generator.
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Global parameters for code generation.
---------------------------------------------------------------------------------------------------
local G = {}

G.indent     = '    '
G.keepindent = true

---------------------------------------------------------------------------------------------------
-- Parameters
---------------------------------------------------------------------------------------------------
local P = {}

P.camelize = false
P.indt     = '   '
P.equalsgn = ': '
P.fieldsep = "' '"

-- Calculate the longest length of the childe's name
local function max_length(node)
    local max_nam_len = 0
    ast.visit_children(node,
        function(n)
            if n.kind == "EnumConstant" or n.kind == "Field" then
                max_nam_len = math.max(max_nam_len, string.len(ast.name(n)))
            end
        end
    )
    return max_nam_len
end

-- Apply parameters to the format string 
local function apply(format)
    local result  = format

    result = string.gsub(result, "<specifier>", P.specifier or '')
    result = string.gsub(result, "<classname>", P.classname or '')
    result = string.gsub(result, "<fieldname>", P.fieldname or '')
    result = string.gsub(result, "<fieldpad>",  P.fieldpad  or '')
    result = string.gsub(result, "<separator>", P.separator or '')
    result = string.gsub(result, "<indent>",    P.indent    or '')

    return result;
end

-- Generate from string function for an enum type node - implementation.
local function from_string_enum_impl(node, specifier)
    log.trace("from_string_enum_impl:", ast.details(node))

    P.specifier = specifier
    P.classname = ast.name(node)
    P.indent    = G.indent

    local maxflen = max_length(node)

    local lines = {}

    table.insert(lines, apply('<specifier> <classname> from_string(std::string_view v)'))
    table.insert(lines, apply('{'))
    table.insert(lines, apply('<indent>int  i = 0;'))
    table.insert(lines, apply('<indent>auto r = std::from_chars(v.begin(), v.end(), i);'))
    table.insert(lines, apply('<indent>if (r.ec != std::errc()) {'))
    table.insert(lines, apply('<indent><indent>throw std::runtime_error("Unable to convert " + std::string(v) + " into an integer.");'))
    table.insert(lines, apply('<indent>}'))

    if G.keepindent then
        table.insert(lines, apply('<indent>// clang-format off'))
    end

    local cnt = ast.count_children(node,
        function(n)
            return n.kind == "EnumConstant"
        end
    )

    table.insert(lines, apply('<indent>bool b ='))

    local idx = 1
    ast.visit_children(node,
        function(n)
            if n.kind == "EnumConstant" then
                P.fieldname = ast.name(n)
                P.fieldpad  = string.rep(' ', maxflen - string.len(P.fieldname))
                if idx == cnt then
                    table.insert(lines, apply('<indent><indent>i == static_cast<std::underlying_type_t<<classname>>>(<classname>::<fieldname>)<fieldpad>;'))
                else
                    table.insert(lines, apply('<indent><indent>i == static_cast<std::underlying_type_t<<classname>>>(<classname>::<fieldname>)<fieldpad> ||'))
                end
                idx = idx + 1
            end
        end
    )

    if G.keepindent then
        table.insert(lines, apply('<indent>// clang-format on'))
    end

    table.insert(lines, apply('<indent>if (!b) {'))
    table.insert(lines, apply('<indent><indent>throw std::runtime_error("Value " + std::to_string(i) + " is outside of <classname> enumeration range.");'))
    table.insert(lines, apply('<indent>}'))

    table.insert(lines, apply('<indent>return static_cast<<classname>>(i);'))
    table.insert(lines, apply('}'))

    for _,l in ipairs(lines) do log.debug(l) end

    return table.concat(lines,"\n")
end

-- Generate to underlying function for an enum type node - implementation.
local function to_underlying_enum_impl(node, specifier)
    log.trace("to_underlying_enum_impl:", ast.details(node))

    P.specifier = specifier
    P.classname = ast.name(node)
    P.indent    = G.indent

    local lines = {}

    table.insert(lines, apply('<specifier> std::underlying_type_t<<classname>> to_underlying(<classname> e)'))
    table.insert(lines, apply('{'))
    table.insert(lines, apply('<indent>return std::underlying_type_t<<classname>>(e);'))
    table.insert(lines, apply('}'))

    for _,l in ipairs(lines) do log.debug(l) end

    return table.concat(lines,"\n")
end

-- Generate from string function snippet for an enum type node.
local function from_string_member_enum_snippet(node)
    log.trace("from_string_member_enum_snippet:", ast.details(node))
    return from_string_enum_impl(node, 'static')
end

local function from_string_template_enum_snippet(node)
    log.trace("from_string_template_enum_snippet:", ast.details(node))
    return from_string_enum_impl(node, 'template <> inline')
end

-- Generate to underlying type conversion function snippet for an enum type node.
local function to_underlying_enum_snippet(node)
    log.trace("to_underlying_enum_snippet:", ast.details(node))
    return to_underlying_enum_impl(node, 'inline')
end

-- Generate from string (member) function snippet item for an enum type node.
local function from_string_member_enum_item(node)
    log.trace("from_string_member_enum_item:", ast.details(node))
    return
    {
        label            = 'from',
        kind             = cmp.lsp.CompletionItemKind.Snippet,
        insertTextMode   = 2,
        insertTextFormat = cmp.lsp.InsertTextFormat.Snippet,
        insertText       = from_string_member_enum_snippet(node)
    }
end

-- Generate from string template function snippet item for an enum type node.
local function from_string_template_enum_item(node)
    log.trace("from_string_template_enum_item:", ast.details(node))
    return
    {
        label            = 'from',
        kind             = cmp.lsp.CompletionItemKind.Snippet,
        insertTextMode   = 2,
        insertTextFormat = cmp.lsp.InsertTextFormat.Snippet,
        insertText       = from_string_template_enum_snippet(node)
    }
end

-- Generate to underlying type conversion function snippet item for an enum type node.
local function to_underlying_enum_item(node)
    log.trace("to_underlying_enum_item:", ast.details(node))
    return
    {
        label            = 'to_u',
        kind             = cmp.lsp.CompletionItemKind.Snippet,
        insertTextMode   = 2,
        insertTextFormat = cmp.lsp.InsertTextFormat.Snippet,
        insertText       = to_underlying_enum_snippet(node)
    }
end

local M = {}

local function is_enum(node)
    return node and node.role == "declaration" and node.kind == "Enum"
end

local function is_class(node)
    return node and node.role == "declaration" and node.kind == "CXXRecord"
end

local enclosing_node = nil
local preceding_node = nil

--- Generator will call this method before presenting set of new candidate nodes
function M.reset()
    enclosing_node = nil
    preceding_node = nil
end

--- Generator will call this method with new candidate node
function M.visit(node, line)
    -- We can generate conversion function for preceding enumeration node
    if ast.precedes(node, line) and is_enum(node) then
        log.debug("visit:", "Acepted preceding node", ast.details(node))
        preceding_node = node
    end
end

--- Generator will call this method to check if the module can generate code
function M.available()
    return enclosing_node or preceding_node
end

-- Generate from string functions for an enum nodes.
function M.completion_items()
    log.trace("completion_items:", ast.details(preceding_node), ast.details(enclosing_node))

    local items = {}

    if is_enum(preceding_node) then
        if is_class(enclosing_node) then
            table.insert(items, from_string_member_enum_item(preceding_node))
        else
            table.insert(items, from_string_template_enum_item(preceding_node))
        end
        table.insert(items, to_underlying_enum_item(preceding_node))
    end

    return items
end

---------------------------------------------------------------------------------------------------
--- Initialization callback
---------------------------------------------------------------------------------------------------
function M.setup(opts)
    if opts then
        if opts.indent then
            G.indent = opts.indent
        end
        if opts.keepindent then
            G.keepindent = opts.keepindent
        end
    end
end

return M
