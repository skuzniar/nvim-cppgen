local ast = require('nvim-cppgen.ast')
local cfg = require('nvim-cppgen.cfg')
local log = require('nvim-cppgen.log')

local cmp = require('cmp')

---------------------------------------------------------------------------------------------------
-- Conversion function generator.
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Parameters
---------------------------------------------------------------------------------------------------
local P = {}

P.droppfix = false
P.camelize = false
P.indt     = '   '
P.equalsgn = ': '
P.fieldsep = "' '"

local function capitalize(s)
    return (string.gsub(s, '^%l', string.upper))
end

local function camelize(s)
    return (string.gsub(s, '%W*(%w+)', capitalize))
end

local function label(name)
    if P.droppfix then
        name = string.gsub(name, '^%a_', '')
    end
    if P.camelize then
        name = camelize(name)
    end

    return name
end

-- Calculate the longest length of the childe's label and name
local function maxlen(node)
    local max_lab_len = 0
    local max_nam_len = 0

    ast.visit_children(node,
        function(n)
            if n.kind == "EnumConstant" or n.kind == "Field" then
                max_lab_len = math.max(max_lab_len, string.len(label(ast.name(n))))
                max_nam_len = math.max(max_nam_len, string.len(ast.name(n)))
            end
        end
    )
    return max_lab_len, max_nam_len
end

-- Apply global parameters to the format string 
local function apply(format)
    local npad = string.rep(' ', P.nlen - string.len(P.name))
    local spec = P.spec or ''

    local result  = format

    result = string.gsub(result, "<spec>", spec)
    result = string.gsub(result, "<name>", P.name)
    result = string.gsub(result, "<indt>", P.indt)
    result = string.gsub(result, "<npad>", npad)
    result = string.gsub(result, "<eqls>", P.equalsgn)
    result = string.gsub(result, "<fsep>", P.fieldsep)

    if (P.pname) then
        result = string.gsub(result, "<pnam>", P.pname)
    end
    if (P.cname) then
        result = string.gsub(result, "<cnam>", P.cname)
    end

    return result;
end

-- Generate from string function for an enum type node - implementation.
local function from_string_enum_impl(node)
    log.trace("from_string_enum_impl:", ast.details(node))
    P.llen, P.nlen = maxlen(node)

    P.name  = ast.name(node)
    P.pname = P.name

    local lines = {}

    table.insert(lines, apply('<spec> <name> from_string(std::string_view v)'))
    table.insert(lines, apply('{'))
    table.insert(lines, apply('<indt>int  i = 0;'))
    table.insert(lines, apply('<indt>auto r = std::from_chars(v.begin(), v.end(), i);'))
    table.insert(lines, apply('<indt>if (r.ec != std::errc()) {'))
    table.insert(lines, apply('<indt><indt>throw std::runtime_error("Unable to convert " + std::string(v) + " into an integer.");'))
    table.insert(lines, apply('<indt>}'))

    if P.keepindt then
        table.insert(lines, apply('<indt>// clang-format off'))
    end

    local cnt = ast.count_children(node,
        function(n)
            return n.kind == "EnumConstant"
        end
    )

    table.insert(lines, apply('<indt>bool b ='))

    local idx = 1
    ast.visit_children(node,
        function(n)
            if n.kind == "EnumConstant" then
                P.name  = ast.name(n)
                P.cname = P.name
                if idx == cnt then
                    table.insert(lines, apply('<indt><indt>i == static_cast<std::underlying_type_t<<pnam>>>(<pnam>::<cnam>)<npad>;'))
                else
                    table.insert(lines, apply('<indt><indt>i == static_cast<std::underlying_type_t<<pnam>>>(<pnam>::<cnam>)<npad> ||'))
                end
                idx = idx + 1
            end
        end
    )

    if P.keepindt then
        table.insert(lines, apply('<indt><indt>// clang-format on'))
    end

    table.insert(lines, apply('<indt>if (!b) {'))
    table.insert(lines, apply('<indt><indt>throw std::runtime_error("Value " + std::to_string(i) + " is outside of <pnam> enumeration range.");'))
    table.insert(lines, apply('<indt>}'))

    table.insert(lines, apply('<indt>return static_cast<<name>>(i);'))
    table.insert(lines, apply('}'))

    for _,l in ipairs(lines) do log.debug(l) end

    return table.concat(lines,"\n")
end

-- Generate to underlying function for an enum type node - implementation.
local function to_underlying_enum_impl(node)
    log.trace("to_underlying_enum_impl:", ast.details(node))
    P.llen, P.nlen = maxlen(node)
    P.name = ast.name(node)

    local lines = {}

    table.insert(lines, apply('<spec> std::underlying_type_t<<name>> to_underlying(<name> e)'))
    table.insert(lines, apply('{'))
    table.insert(lines, apply('<indt>return std::underlying_type_t<<name>>(e);'))
    table.insert(lines, apply('}'))

    for _,l in ipairs(lines) do log.debug(l) end

    return table.concat(lines,"\n")
end

-- Generate from string function snippet for an enum type node.
local function from_string_member_enum_snippet(node)
    log.trace("from_string_member_enum_snippet:", ast.details(node))
    P.spec = 'static'
    return from_string_enum_impl(node)
end

local function from_string_template_enum_snippet(node)
    log.trace("from_string_template_enum_snippet:", ast.details(node))
    P.spec = 'template <> inline'
    return from_string_enum_impl(node)
end

-- Generate to underlying type conversion function snippet for an enum type node.
local function to_underlying_enum_snippet(node)
    log.trace("to_underlying_enum_snippet:", ast.details(node))
    P.spec = 'inline'
    return to_underlying_enum_impl(node)
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

local function isEnum(node)
    return node and node.role == "declaration" and (node.kind == "Enum" or node.kind == "Field")
end

local function isClass(node)
    return node and node.role == "declaration" and (node.kind == "CXXRecord" or node.kind == "Field")
end

--- Returns true if the node is of interest to us
function M.interesting(preceding, _)
    -- We can generate conversion function for preceding enumeration node
    if isEnum(preceding) then
        return true
    end
    return false
end

-- Generate from string functions for an enum nodes.
function M.completion_items(preceding, enclosing)
    log.trace("completion_items:", ast.details(preceding), ast.details(enclosing))

    P.droppfix = cfg.options.cnv and cfg.options.cnv.drop_prefix
    P.camelize = cfg.options.cnv and cfg.options.cnv.camelize
    P.keepindt = cfg.options.cnv and cfg.options.cnv.keep_indentation
    if cfg.options.cnv and cfg.options.cnv.indentation then
        P.indt = cfg.options.cnv.indentation
    end
    if cfg.options.cnv and cfg.options.cnv.equal_sign then
        P.equalsgn = cfg.options.cnv.equal_sign
    end
    if cfg.options.cnv and cfg.options.cnv.field_separator then
        P.fieldsep = cfg.options.cnv.field_separator
    end
    if cfg.options.cnv and cfg.options.cnv.print_class_name then
        P.printcname = cfg.options.cnv.print_class_name
    end

    local items = {}

    if isEnum(preceding) then
        if isClass(enclosing) then
            table.insert(items, from_string_member_enum_item(preceding))
        else
            table.insert(items, from_string_template_enum_item(preceding))
        end
        table.insert(items, to_underlying_enum_item(preceding))
    end

    return items
end

return M
