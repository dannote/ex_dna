defmodule ExDNA.AST.AnnotatorTest do
  use ExUnit.Case, async: true

  alias ExDNA.AST.Annotator

  describe "strip_no_clone/1" do
    test "removes def preceded by @no_clone true" do
      ast =
        Code.string_to_quoted!("""
        defmodule Foo do
          @no_clone true
          def skip_me(x), do: x + 1

          def keep_me(x), do: x * 2
        end
        """)

      stripped = Annotator.strip_no_clone(ast)
      code = Macro.to_string(stripped)

      refute code =~ "skip_me"
      assert code =~ "keep_me"
      refute code =~ "no_clone"
    end

    test "removes defp preceded by @no_clone true" do
      ast =
        Code.string_to_quoted!("""
        defmodule Foo do
          @no_clone true
          defp helper(x), do: x + 1

          def public(x), do: x * 2
        end
        """)

      stripped = Annotator.strip_no_clone(ast)
      code = Macro.to_string(stripped)

      refute code =~ "helper"
      assert code =~ "public"
    end

    test "keeps def without @no_clone annotation" do
      ast =
        Code.string_to_quoted!("""
        defmodule Foo do
          def alpha(x), do: x + 1
          def beta(x), do: x * 2
        end
        """)

      stripped = Annotator.strip_no_clone(ast)
      code = Macro.to_string(stripped)

      assert code =~ "alpha"
      assert code =~ "beta"
    end

    test "removes multiple annotated defs" do
      ast =
        Code.string_to_quoted!("""
        defmodule Foo do
          @no_clone true
          def skip_a(x), do: x + 1

          @no_clone true
          def skip_b(x), do: x - 1

          def keep(x), do: x * 2
        end
        """)

      stripped = Annotator.strip_no_clone(ast)
      code = Macro.to_string(stripped)

      refute code =~ "skip_a"
      refute code =~ "skip_b"
      assert code =~ "keep"
    end

    test "handles nested modules" do
      ast =
        Code.string_to_quoted!("""
        defmodule Outer do
          defmodule Inner do
            @no_clone true
            def skip(x), do: x

            def keep(x), do: x + 1
          end

          def outer_keep(x), do: x * 3
        end
        """)

      stripped = Annotator.strip_no_clone(ast)
      code = Macro.to_string(stripped)

      refute code =~ "skip"
      assert code =~ "keep"
      assert code =~ "outer_keep"
    end

    test "does not strip when @no_clone is not followed by def" do
      ast =
        Code.string_to_quoted!("""
        defmodule Foo do
          @no_clone true
          @moduledoc "hello"

          def keep(x), do: x
        end
        """)

      stripped = Annotator.strip_no_clone(ast)
      code = Macro.to_string(stripped)

      assert code =~ "keep"
      assert code =~ "moduledoc"
    end

    test "passes through AST without defmodule unchanged" do
      ast =
        Code.string_to_quoted!("""
        x = 1 + 2
        """)

      assert Annotator.strip_no_clone(ast) == ast
    end
  end
end
