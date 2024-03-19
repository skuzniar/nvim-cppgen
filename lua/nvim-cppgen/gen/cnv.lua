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

-- Apply node object to the format string 
local function apply(format, node)
    local name = ast.name(node)
    local labl = label(ast.name(node))
    local lpad = string.rep(' ', P.llen - string.len(labl))
    local npad = string.rep(' ', P.nlen - string.len(name))
    local spec = P.spec or ''

    local result  = format

    result = string.gsub(result, "<spec>", spec)
    result = string.gsub(result, "<name>", name)
    result = string.gsub(result, "<labl>", labl)
    result = string.gsub(result, "<indt>", P.indt)
    result = string.gsub(result, "<lpad>", lpad)
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

    P.pname = ast.name(node) 

    local lines = {}

    table.insert(lines, apply('<spec> <name> from_string(std::string_view v)', node))
    table.insert(lines, apply('{', node))
    table.insert(lines, apply('<indt>int  i = 0;', node))
    table.insert(lines, apply('<indt>auto r = std::from_chars(v.begin(), v.end(), i);', node))
    table.insert(lines, apply('<indt>if (r.ec != std::errc()) {', node))
    table.insert(lines, apply('<indt><indt>throw std::runtime_error("Unable to convert " + std::string(v) + " into an integer.");' , node))
    table.insert(lines, apply('<indt>}', node))

    if P.keepindt then
        table.insert(lines, apply('<indt>// clang-format off', node))
    end

    local cnt = ast.count_children(node,
        function(n)
            return n.kind == "EnumConstant"
        end
    )

    table.insert(lines, apply('<indt>bool b =', node))

    local idx = 1
    ast.visit_children(node,
        function(n)
            if n.kind == "EnumConstant" then
                P.cname = ast.name(n) 
                if idx == cnt then
                    table.insert(lines, apply('<indt><indt>i == static_cast<std::underlying_type_t<<pnam>>>(<pnam>::<cnam>)<npad>;', n))
                else
                    table.insert(lines, apply('<indt><indt>i == static_cast<std::underlying_type_t<<pnam>>>(<pnam>::<cnam>)<npad> ||', n))
                end
                idx = idx + 1
            end
        end
    )

    if P.keepindt then
        table.insert(lines, apply('<indt><indt>// clang-format on', node))
    end

    table.insert(lines, apply('<indt>if (!b) {', node))
    table.insert(lines, apply('<indt><indt>throw std::runtime_error("Value " + std::to_string(i) + " is outside of enumeration range.");' , node))
    table.insert(lines, apply('<indt>}', node))

    table.insert(lines, apply('<indt>return static_cast<<name>>(i);' , node))
    table.insert(lines, apply('}', node))

    for _,l in ipairs(lines) do log.debug(l) end

    return table.concat(lines,"\n")
end

-- Generate from string function snippet for an enum type node.
local function from_string_enum_snippet(node)
    log.trace("from_string_enum_snippet:", ast.details(node))
    P.spec = 'inline'
    return from_string_enum_impl(node)
end

-- Generate from string function snippet item for an enum type node.
local function from_string_enum_item(node)
    log.trace("from_string_enum_item:", ast.details(node))
    return
    {
        label            = 'from',
        kind             = cmp.lsp.CompletionItemKind.Snippet,
        insertTextMode   = 2,
        insertTextFormat = cmp.lsp.InsertTextFormat.Snippet,
        insertText       = from_string_enum_snippet(node)
    }
end

local M = {}

local function isEnum(node)
    return node and node.role == "declaration" and (node.kind == "Enum" or node.kind == "Field")
end

--- Returns true if the node is of interest to us
function M.interesting(preceding, enclosing)
    -- We can generate shift operator for preceding enumeration node and both preceding and enclosing class nodes
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
        table.insert(items, from_string_enum_item(preceding))
    end

    return items
end

return M
