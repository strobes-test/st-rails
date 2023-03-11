# frozen_string_literal: true

require "active_support/time_with_zone"

module ActiveRecord
  module ConnectionAdapters
    module MySQL
      module Quoting # :nodoc:
        def quote(value)
          case value
          when String
            if value.encoding == Encoding::BINARY
              quoted_binary(value)
            else
              "'#{quote_string(value.to_s)}'"
            end
          else
            super
          end
        end

        def cast_bound_value(value)
          case value
          when Rational
            value.to_f.to_s
          when BigDecimal
            # For Ruby 2.7, the string returned by `to_s` is ASCII-8BIT.
            # We want to avoid that, as that will cause the string to be quoted as
            # binary. It is safe to force the encoding to US-ASCII.
            value.to_s("F").force_encoding(Encoding::US_ASCII)
          when Numeric
            value.to_s
          when true
            "1"
          when false
            "0"
          when ActiveSupport::Duration
            warn_quote_duration_deprecated
            value.to_s
          else
            value
          end
        end

        def quote_column_name(name)
          self.class.quoted_column_names[name] ||= "`#{super.gsub('`', '``')}`"
        end

        def quote_table_name(name)
          self.class.quoted_table_names[name] ||= super.gsub(".", "`.`").freeze
        end

        def unquoted_true
          1
        end

        def unquoted_false
          0
        end

        def quoted_date(value)
          if supports_datetime_with_precision?
            super
          else
            super.sub(/\.\d{6}\z/, "")
          end
        end

        def quoted_binary(value)
          if value.is_a? String
            "x'#{value.unpack1("H*")}'"
          else
            "x'#{value.hex}'"
          end
        end

        def unquote_identifier(identifier)
          if identifier && identifier.start_with?("`")
            identifier[1..-2]
          else
            identifier
          end
        end

        # Override +type_cast+ we pass to mysql2 Date and Time objects instead
        # of Strings since mysql2 is able to handle those classes more efficiently.
        def type_cast(value) # :nodoc:
          case value
          when ActiveSupport::TimeWithZone
            # We need to check explicitly for ActiveSupport::TimeWithZone because
            # we need to transform it to Time objects but we don't want to
            # transform Time objects to themselves.
            if default_timezone == :utc
              value.getutc
            else
              value.getlocal
            end
          when Date, Time
            value
          else
            super
          end
        end

        def column_name_matcher
          COLUMN_NAME
        end

        def column_name_with_order_matcher
          COLUMN_NAME_WITH_ORDER
        end

        COLUMN_NAME = /
          \A
          (
            (?:
              # `table_name`.`column_name` | function(one or no argument)
              ((?:\w+\.|`\w+`\.)?(?:\w+|`\w+`) | \w+\((?:|\g<2>)\))
            )
            (?:(?:\s+AS)?\s+(?:\w+|`\w+`))?
          )
          (?:\s*,\s*\g<1>)*
          \z
        /ix

        COLUMN_NAME_WITH_ORDER = /
          \A
          (
            (?:
              # `table_name`.`column_name` | function(one or no argument)
              ((?:\w+\.|`\w+`\.)?(?:\w+|`\w+`) | \w+\((?:|\g<2>)\))
            )
            (?:\s+COLLATE\s+(?:\w+|"\w+"))?
            (?:\s+ASC|\s+DESC)?
          )
          (?:\s*,\s*\g<1>)*
          \z
        /ix

        private_constant :COLUMN_NAME, :COLUMN_NAME_WITH_ORDER
      end
    end
  end
end
