# Nvim-cppgen
Neovim C++ code generator. Currently can generate output stream operators for classes and enumerations.

## Install

```txt
{
    --"skuzniar/nvim-cppgen",
    dir = "/Users/slawomir/dvlp/nvim-cppgen",
    dependencies = {
        "neovim/nvim-lspconfig"
    },
    opts =
    {
        log = {
            plugin      = 'nvim-cppgen',
            level       = 'info',
            use_console = false
        },
        -- Output Stream Shift operator generator
        oss = {
            drop_prefix      = true,
            camelize         = true,
            keep_indentation = false,
            indentation      = '    ',
            equal_sign       = ': ',
            field_separator  = "' '",
            print_class_name = [['[' << "<name>" << ']' << '=']]

            --[[
            class ClassName
            {
                std::string m_first_name;

                friend std::ostream& operator<<(std::ostream& s, const Name& o)
                {
                    // clang-format off
                    s << '[' << "ClassName" << ']' << '=';
                    s << "FirstName: " << o.m_first_name << ' ';
                    // clang-format on
                    return s;
                }
            };
            ]]
        }
    },
}
```

